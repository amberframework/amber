## 2026-06-11 - [XSS in Default Error Handler]
**Vulnerability:** Reflected Cross-Site Scripting (XSS) in default HTML error response.
**Learning:** The default error controller generated raw HTML incorporating the unescaped Exception message. In Crystal, `Exception#message` can be `nil` (`String?`), so safely interpolating it into HTML requires `HTML.escape(@ex.message || "")` and explicitly requiring the `"html"` module.
**Prevention:** Always escape user-controllable or dynamic string data, including exception messages, before interpolating it into an HTML template or string.

## 2026-06-12 - Unhandled IndexError in Cryptography Routines (DoS Vector)
**Vulnerability:** Amber's `MessageVerifier` and `MessageEncryptor` attempted to slice arrays and decrypt payloads before checking the bounds of the provided data (`IndexError` due to missing `split` size check and negative offsets in slices). This allows an attacker to send an invalid cookie or payload that crashes the worker.
**Learning:** Crystal's array slicing and destructuring raise `IndexError` when bounds are not met, which propagates to an uncaught 500 error instead of a graceful rejection. Always check payload sizes before executing cryptography functions.
**Prevention:** Always validate size and structure before extracting signatures, IVs, or payload data from untrusted inputs in cryptography routines. Add `size` bounds checks and safely handle destructuring.

## 2026-06-13 - Command Injection in CLI Utilities
**Vulnerability:** Command injection in `src/amber/cli/commands/encrypt.cr` via string interpolation in the `system(...)` command (`system("#{options.editor} #{unencrypted_file}")`). If `env` or `editor` contains shell special characters, arbitrary commands could be executed.
**Learning:** Passing a single string to `system(...)` causes it to be evaluated by a shell, allowing shell meta-characters to alter execution. User-controlled variables interpolated into this string create command injection vulnerabilities.
**Prevention:** Avoid string interpolation when calling system commands. Use the array form of `system(executable, args_array)` or `Process.run(executable, args_array)` to bypass the shell entirely and pass arguments safely.
