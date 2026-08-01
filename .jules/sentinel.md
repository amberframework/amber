## 2024-05-24 - [Missing Default Security Headers]
**Vulnerability:** Newly generated Amber framework apps omit foundational HTTP security headers (e.g., XSS Protection, Content-Type Options).
**Learning:** The pipeline configuration in `routes.cr.ecr` lacked a dedicated middleware pipe to enforce baseline security headers for web routes.
**Prevention:** Always include a SecureHeaders middleware in the default web pipeline to ensure a defense-in-depth posture out of the box.
## 2026-06-11 - [XSS in Default Error Handler]
**Vulnerability:** Reflected Cross-Site Scripting (XSS) in default HTML error response.
**Learning:** The default error controller generated raw HTML incorporating the unescaped Exception message. In Crystal, `Exception#message` can be `nil` (`String?`), so safely interpolating it into HTML requires `HTML.escape(@ex.message || "")` and explicitly requiring the `"html"` module.
**Prevention:** Always escape user-controllable or dynamic string data, including exception messages, before interpolating it into an HTML template or string.
## 2026-06-16 - Unhandled IndexError Hardening in Cryptography Routines
**Vulnerability:** Amber's `MessageVerifier` and `MessageEncryptor` attempted to slice arrays and decrypt payloads before checking the bounds of the provided data (`IndexError` due to missing `split` size check and negative offsets in slices). While top-level middleware rescues and returns a 500 status code, these classes should gracefully reject malformed payloads themselves with custom exceptions.
**Learning:** Crystal's array slicing and destructuring raise `IndexError` when bounds are not met, which propagates to an uncaught exception instead of a graceful rejection. Always check payload sizes before executing cryptography functions.
**Prevention:** Always validate size and structure before extracting signatures, IVs, or payload data from untrusted inputs in cryptography routines. Add `size` bounds checks and safely handle destructuring, raising typed exceptions like `InvalidSignature` and `InvalidMessage`.
## 2024-06-13 - Command Injection in CLI Utilities
**Vulnerability:** Command injection in `src/amber/cli/commands/encrypt.cr` via string interpolation in the `system(...)` command (`system("#{options.editor} #{unencrypted_file}")`). If `env` or `editor` contains shell special characters, arbitrary commands could be executed.
**Learning:** Passing a single string to `system(...)` causes it to be evaluated by a shell, allowing shell meta-characters to alter execution. User-controlled variables interpolated into this string create command injection vulnerabilities.
**Prevention:** Avoid string interpolation when calling system commands. Use the array form of `system(executable, args_array)` or `Process.run(executable, args_array)` to bypass the shell entirely and pass arguments safely.
