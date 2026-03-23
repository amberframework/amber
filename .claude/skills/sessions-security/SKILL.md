---
name: amber-sessions-security
description: Amber V2 session management and security — session stores, cookies, encryption, key rotation, CSRF, SameSite, session regeneration
user-invocable: false
---

# Amber Sessions and Security

Amber provides a layered session and cookie security system built on encrypted cookies, pluggable server-side adapters, HMAC verification, AES-256 encryption, CSRF protection, and session fixation defenses.

## Session Store Types

Amber has two session store implementations, both inheriting from `Amber::Router::Session::AbstractStore`.

### CookieStore

Stores all session data serialized as JSON directly inside the cookie. The cookie is either signed (HMAC-verified) or encrypted (AES-256-CBC + HMAC), depending on configuration.

Use CookieStore when:
- Session data is small (total must fit within the 4096-byte cookie limit)
- No server-side session infrastructure is needed
- Stateless deployments are preferred

Limitations:
- 4 KB maximum per cookie (enforced by `Amber::Router::Cookies::MAX_COOKIE_SIZE`)
- All data travels with every request
- Session regeneration (`regenerate_session!`) is a no-op
- No server-side expiration or sliding TTL

### AdapterSessionStore

Stores session data server-side using a pluggable adapter. Only the session ID is stored in an encrypted cookie. The adapter handles all read/write/expiration operations.

Use AdapterSessionStore when:
- Session data may exceed 4 KB
- Server-side session control is needed (forced logout, TTL, sliding expiration)
- Session regeneration is required for authentication flows
- Multi-instance deployments share a session backend (e.g., Redis, database)

The adapter is selected by name through `Amber::Adapters::AdapterFactory.create_session_adapter`.

## Session Configuration

Session settings live in the environment YAML file under the `session` key and map to `Amber::Environment::Settings#session`:

```yaml
# config/environments/development.yml
session:
  key: "amber.session"         # cookie name
  store: "encrypted_cookie"    # "signed_cookie", "encrypted_cookie", or "redis"
  expires: 0                   # TTL in seconds (0 = browser session)
  adapter: "memory"            # adapter name for server-side stores
```

### SessionConfig Properties

| Property  | Type     | Default            | Description |
|-----------|----------|--------------------|-------------|
| `key`     | `String` | `"amber.session"`  | Name of the session cookie |
| `store`   | `String` | `"signed_cookie"`  | Cookie security mode: `"signed_cookie"`, `"encrypted_cookie"`, or `"redis"` |
| `expires` | `Int32`  | `0`                | Session TTL in seconds. `0` means the cookie expires when the browser closes |
| `adapter` | `String` | `"memory"`         | Server-side storage adapter name |

The `store` value determines how cookie data is protected:
- `"signed_cookie"` -- HMAC-SHA256 signature, data is Base64-readable but tamper-proof
- `"encrypted_cookie"` -- AES-256-CBC encryption + HMAC-SHA256 signature, data is opaque
- `"redis"` -- maps to `:redis` store type (requires a Redis session adapter)

The `secret_key_base` property on Settings provides the master secret for all cookie signing and encryption. It must be at least 32 characters in production.

```yaml
# config/environments/production.yml
secret_key_base: "a-long-random-string-at-least-32-characters"
previous_secrets:
  - "the-old-secret-being-rotated-out"
```

## Reading, Writing, and Deleting Session Values

Session data is accessed through `context.session` in controllers and pipes. Both `String` and `Symbol` keys are accepted.

```crystal
class SessionController < Amber::Controller::Base
  def create
    # Write a value
    context.session["user_id"] = current_user.id.to_s
    context.session[:locale] = "en"

    # Read a value (returns String? for adapter store, String? for cookie store)
    user_id = context.session["user_id"]?
    locale = context.session[:locale]?

    # Read with a default fallback
    theme = context.session.fetch("theme", "light")

    # Check for key existence (AdapterSessionStore)
    if context.session.has_key?("user_id")
      # ...
    end

    # Delete a single key
    context.session.delete("temporary_token")

    # Destroy the entire session
    context.session.destroy

    # Bulk update
    context.session.update({"key1" => "val1", "key2" => "val2"})
  end
end
```

The `Amber::Pipe::Session` pipe automatically persists session changes after the request completes. You do not need to call `set_session` manually.

## CookieStore Internals

`Amber::Router::Session::CookieStore` serializes a `SessionHash` to JSON and stores it in the cookie via either `cookies.signed` or `cookies.encrypted`.

```
Request → Read cookie → Decrypt/Verify → JSON.parse → SessionHash
                                                          ↓
Response ← Write cookie ← Encrypt/Sign ← JSON.to_json ← SessionHash (if changed)
```

The `SessionHash` tracks whether any value has changed. The session cookie is only rewritten when `changed?` returns `true`.

Cookie security flags set automatically:
- `http_only: true` -- prevents JavaScript access
- `secure: true` -- in non-development/test environments (HTTPS only)
- `samesite: Lax` -- default SameSite policy

If the serialized cookie exceeds 4096 bytes, an `Amber::Exceptions::CookieOverflow` is raised.

## AdapterSessionStore Internals

`Amber::Router::Session::AdapterSessionStore` generates a UUID-based session ID (`"amber.session:<uuid>"`), stores it in an encrypted cookie, and delegates all data operations to the adapter.

```
Request → Read encrypted cookie → Extract session_id
              ↓
         adapter.get(session_id, key) → value

Response → adapter.set(session_id, key, value)  (on change)
         → adapter.expire(session_id, ttl)       (sliding expiration)
         → Write encrypted cookie with session_id
```

### Memory Adapter

`Amber::Adapters::MemorySessionAdapter` is the built-in default. It stores sessions in a thread-safe `Hash` protected by a `Mutex`, with TTL support and automatic background cleanup of expired sessions every 60 seconds.

Suitable for development, testing, and single-instance production deployments. Session data is lost on application restart.

### Writing a Custom Adapter

Implement all abstract methods from `Amber::Adapters::SessionAdapter`:

```crystal
class DatabaseSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@db : DB::Database)
  end

  def get(session_id : String, key : String) : String?
    @db.query_one?("SELECT value FROM sessions WHERE sid = $1 AND key = $2",
                   session_id, key, as: String)
  end

  def set(session_id : String, key : String, value : String) : Nil
    @db.exec("INSERT INTO sessions (sid, key, value) VALUES ($1, $2, $3)
              ON CONFLICT (sid, key) DO UPDATE SET value = $3",
             session_id, key, value)
  end

  def delete(session_id : String, key : String) : Nil
    @db.exec("DELETE FROM sessions WHERE sid = $1 AND key = $2", session_id, key)
  end

  def destroy(session_id : String) : Nil
    @db.exec("DELETE FROM sessions WHERE sid = $1", session_id)
  end

  def exists?(session_id : String, key : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE sid = $1 AND key = $2",
                  session_id, key, as: Int64) > 0
  end

  def keys(session_id : String) : Array(String)
    @db.query_all("SELECT key FROM sessions WHERE sid = $1", session_id, as: String)
  end

  def values(session_id : String) : Array(String)
    @db.query_all("SELECT value FROM sessions WHERE sid = $1", session_id, as: String)
  end

  def to_hash(session_id : String) : Hash(String, String)
    hash = Hash(String, String).new
    @db.query("SELECT key, value FROM sessions WHERE sid = $1", session_id) do |rs|
      rs.each { hash[rs.read(String)] = rs.read(String) }
    end
    hash
  end

  def empty?(session_id : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE sid = $1",
                  session_id, as: Int64) == 0
  end

  def expire(session_id : String, seconds : Int32) : Nil
    expires_at = Time.utc + seconds.seconds
    @db.exec("UPDATE sessions SET expires_at = $2 WHERE sid = $1",
             session_id, expires_at)
  end

  def batch_set(session_id : String, hash : Hash(String, String)) : Nil
    hash.each { |k, v| set(session_id, k, v) }
  end

  def batch(session_id : String, &block : Amber::Adapters::SessionBatchOperations ->) : Nil
    # Implement batch operations
  end
end
```

Required abstract methods:

| Method | Signature | Purpose |
|--------|-----------|---------|
| `get` | `(session_id, key) : String?` | Retrieve a single value |
| `set` | `(session_id, key, value) : Nil` | Store a single value |
| `delete` | `(session_id, key) : Nil` | Remove a single key |
| `destroy` | `(session_id) : Nil` | Remove entire session |
| `exists?` | `(session_id, key) : Bool` | Check key existence |
| `keys` | `(session_id) : Array(String)` | List all keys |
| `values` | `(session_id) : Array(String)` | List all values |
| `to_hash` | `(session_id) : Hash(String, String)` | Full session snapshot |
| `empty?` | `(session_id) : Bool` | Check if session has data |
| `expire` | `(session_id, seconds) : Nil` | Set TTL |
| `batch_set` | `(session_id, hash) : Nil` | Bulk write |
| `batch` | `(session_id, &block) : Nil` | Atomic batch operations |

Optional overrides with defaults:
- `close : Nil` -- cleanup on shutdown (default: no-op)
- `healthy? : Bool` -- health check (default: `true`)

Register the adapter with the factory so it can be selected by name in configuration.

## MessageEncryptor and MessageVerifier

These two classes in `Amber::Support` provide the cryptographic foundation for all cookie security.

### MessageVerifier

Signs data with HMAC to prevent tampering. Used by `SignedStore` cookies.

- Digest algorithm: SHA-256 (default)
- Format: `Base64(data)--Base64(HMAC(data))`
- Verification uses constant-time comparison (`Crypto::Subtle.constant_time_compare`) to prevent timing attacks
- Supports key rotation via `previous_secrets`

### MessageEncryptor

Encrypts and signs data for full confidentiality. Used by `EncryptedStore` cookies.

- Cipher: AES-256-CBC
- Digest: SHA-256 for HMAC signatures
- Key derivation: HMAC-SHA256 derives separate encryption and signing keys from the master secret using purpose strings (`"amber.encryption"` and `"amber.signing"`)
- Format: `encrypted_data | IV | HMAC_signature` (binary, then Base64-encoded for cookies)
- Decryption verifies the HMAC signature first to prevent padding oracle attacks
- Supports key rotation via `previous_secrets`

Both classes receive `previous_secrets` from `Amber.settings.previous_secrets`, which is configured in the environment YAML.

## SameSite Cookie Policy

Both `CookieStore` and `AdapterSessionStore` set `SameSite=Lax` on session cookies by default. This is configured in the `set_session` method of each store.

The `secure` flag is automatically set to `true` in non-development and non-test environments:

```crystal
# From both CookieStore#set_session and AdapterSessionStore#set_session
secure = !Amber.env.development? && !Amber.env.test?
samesite = HTTP::Cookie::SameSite::Lax
```

All session cookies are also set with `http_only: true` to prevent client-side JavaScript access.

## Session Regeneration

Session regeneration prevents session fixation attacks by issuing a new session ID after authentication or privilege changes. This is only supported by `AdapterSessionStore`; it is a no-op for `CookieStore`.

Call `context.regenerate_session!` after successful login:

```crystal
class SessionsController < Amber::Controller::Base
  def create
    user = User.authenticate(params["email"], params["password"])

    if user
      # Regenerate session ID to prevent fixation attacks
      context.regenerate_session!

      # Store the authenticated user
      context.session["user_id"] = user.id.to_s

      redirect_to "/dashboard"
    else
      flash["error"] = "Invalid credentials"
      redirect_to "/login"
    end
  end

  def destroy
    context.session.destroy
    redirect_to "/login"
  end
end
```

What `regenerate_id` does internally:
1. Reads all data from the current session
2. Generates a new UUID-based session ID
3. Copies existing data to the new session via `batch_set`
4. Sets expiration on the new session (if TTL is configured)
5. Destroys the old session
6. Marks the session as changed so the new ID cookie is written on response

## Sliding Expiration

When `expires` is set to a value greater than `0`, `AdapterSessionStore` supports sliding expiration. On every request, the `Amber::Pipe::Session` pipe calls `touch` on the session store, which resets the TTL:

```crystal
# From Amber::Pipe::Session#call
if session.is_a?(Amber::Router::Session::AdapterSessionStore)
  session.touch
end
```

The `touch` method calls `adapter.expire(session_id, @expires)` to reset the countdown. This means a session that is actively used will never expire, while idle sessions expire after the configured number of seconds.

Configure sliding expiration in your environment YAML:

```yaml
session:
  key: "amber.session"
  store: "encrypted_cookie"
  expires: 3600    # session expires after 1 hour of inactivity
  adapter: "memory"
```

## CSRF Integration

The `Amber::Pipe::CSRF` pipe stores and validates CSRF tokens using the session. The token is stored under the key `"csrf.token"`.

### How it works

1. On the first GET request, `real_session_token` generates a random 32-byte token via `Random::Secure.urlsafe_base64(32)` and stores it in `context.session["csrf.token"]`
2. Templates include the token in forms using `Amber::Pipe::CSRF.tag(context)` or `Amber::Pipe::CSRF.metatag(context)`
3. On `PUT`, `POST`, `PATCH`, `DELETE` requests, the pipe validates the submitted token against the session token
4. If validation fails, `Amber::Exceptions::Forbidden` is raised

### Token strategies

**PersistentToken** (default): The session stores a single base token. Each rendered form gets a one-time-pad masked version of this token. Validation unmasks the submitted token and compares it to the session token using constant-time comparison. This prevents BREACH compression attacks because the token value changes on every page load.

```crystal
# In templates
<%= Amber::Pipe::CSRF.tag(context) %>
# Produces: <input type="hidden" name="_csrf" value="<masked-token>" />

# For AJAX — include as a meta tag and send via header
<%= Amber::Pipe::CSRF.metatag(context) %>
# Produces: <meta name="_csrf" content="<masked-token>" />
# JavaScript sends it as X-CSRF-TOKEN header
```

**RefreshableToken**: The session token is used directly (no masking). After validation, the token is deleted from the session, so each token is single-use. Simpler but not BREACH-resistant.

```crystal
# Switch strategy globally
Amber::Pipe::CSRF.token_strategy = Amber::Pipe::CSRF::RefreshableToken
```

The CSRF token is read from either the `_csrf` form parameter or the `X-CSRF-TOKEN` request header.

## Key Rotation

Key rotation allows you to change `secret_key_base` without invalidating all existing sessions and cookies. Old secrets are listed in `previous_secrets`.

### How it works

**MessageVerifier** (signed cookies):
1. Verification first tries the current secret
2. If that fails, it iterates through `previous_secrets` and tries each one
3. If any old secret produces a valid HMAC, the data is returned
4. New signatures always use the current secret

**MessageEncryptor** (encrypted cookies):
1. Decryption first tries the current derived keys
2. If that fails, it derives keys from each entry in `previous_secrets` and tries them
3. It also tries legacy single-key format (where secret was used directly as both encryption and signing key) for backward compatibility with pre-V2 Amber
4. New encryption always uses the current secret

### Rotation workflow

```yaml
# Step 1: Add the new secret and move the old one to previous_secrets
secret_key_base: "new-secret-key-at-least-32-characters"
previous_secrets:
  - "old-secret-key-that-was-previously-active"

# Step 2: After all old sessions have expired, remove the old secret
secret_key_base: "new-secret-key-at-least-32-characters"
previous_secrets: []
```

The `previous_secrets` array is passed through to `Amber::Router::Cookies::Store#encrypted` and `#signed`, which forward it to `MessageEncryptor` and `MessageVerifier` respectively:

```crystal
# From Cookies::Store
def encrypted
  @encrypted ||= EncryptedStore.new(self, @secret, previous_secrets: Amber.settings.previous_secrets)
end

def signed
  @signed ||= SignedStore.new(self, @secret, previous_secrets: Amber.settings.previous_secrets)
end
```

## Session Security Best Practices

1. **Always use encrypted cookies in production.** Set `store: "encrypted_cookie"` so session data is not readable by clients. Signed cookies prevent tampering but the data is Base64-visible.

2. **Set a strong `secret_key_base`.** At least 32 characters of cryptographically random data. Amber validates this in production and raises `ConfigurationError` if it is too short or empty.

3. **Regenerate session IDs after login.** Call `context.regenerate_session!` immediately after successful authentication to prevent session fixation attacks. Use `AdapterSessionStore` (not CookieStore) to get this capability.

4. **Configure session expiration.** Set `expires` to a reasonable value (e.g., 3600 for 1 hour). This activates both cookie expiration and server-side TTL with sliding expiration for adapter-based sessions.

5. **Use the default SameSite=Lax policy.** This prevents the session cookie from being sent on cross-origin requests initiated by third-party sites, mitigating CSRF in browsers that support SameSite.

6. **Keep CSRF protection enabled for all state-changing routes.** The `Amber::Pipe::CSRF` pipe should be in the `:web` pipeline. Use `PersistentToken` (default) for BREACH resistance.

7. **Rotate secrets gracefully.** Use `previous_secrets` to allow old sessions to continue working during key rotation. Remove old secrets only after all sessions signed with them have expired.

8. **Destroy sessions on logout.** Call `context.session.destroy` to remove all session data. For adapter-based sessions this also removes data from the backend store.

9. **Do not store sensitive data in CookieStore sessions.** Even with encryption, minimizing what is stored in cookies reduces exposure. Prefer adapter-based sessions for sensitive data and store only session IDs in cookies.

10. **Use HTTPS in production.** The `secure` cookie flag is automatically set in non-development environments, but it only works over HTTPS. Ensure your production deployment uses TLS.

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/router/session.cr` | Session module entry point |
| `src/amber/router/session/abstract_store.cr` | `AbstractStore` -- session store interface |
| `src/amber/router/session/cookie_store.cr` | `CookieStore` and `SessionHash` -- cookie-based sessions |
| `src/amber/router/session/adapter_session_store.cr` | `AdapterSessionStore` -- server-side sessions with adapters |
| `src/amber/router/session/session_store.cr` | `Store` -- factory that builds the appropriate session store |
| `src/amber/router/cookies/store.cr` | `Cookies::Store` -- cookie jar with signed/encrypted sub-stores |
| `src/amber/router/cookies/encrypted_store.cr` | `EncryptedStore` -- AES-256-CBC encrypted cookies |
| `src/amber/router/cookies/signed_store.cr` | `SignedStore` -- HMAC-signed cookies |
| `src/amber/router/cookies/abstract_store.cr` | `Cookies::AbstractStore` -- cookie store interface |
| `src/amber/support/message_encryptor.cr` | `MessageEncryptor` -- AES-256-CBC + HMAC-SHA256 with key rotation |
| `src/amber/support/message_verifier.cr` | `MessageVerifier` -- HMAC-SHA256 signing with key rotation |
| `src/amber/support/file_encryptor.cr` | `FileEncryptor` -- encrypts/decrypts files using MessageEncryptor |
| `src/amber/adapters/session_adapter.cr` | `SessionAdapter` -- abstract adapter interface |
| `src/amber/adapters/memory_session_adapter.cr` | `MemorySessionAdapter` -- in-memory adapter with TTL |
| `src/amber/pipes/session.cr` | `Amber::Pipe::Session` -- session persistence and sliding expiration |
| `src/amber/pipes/csrf.cr` | `Amber::Pipe::CSRF` -- CSRF token generation and validation |
| `src/amber/configuration/session_config.cr` | `SessionConfig` -- typed session configuration |
| `src/amber/router/context.cr` | `HTTP::Server::Context` -- `regenerate_session!` method |
| `src/amber/environment/settings.cr` | `Settings` -- `secret_key_base`, `previous_secrets`, session config |
