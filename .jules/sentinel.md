## 2026-06-11 - [XSS in Default Error Handler]
**Vulnerability:** Reflected Cross-Site Scripting (XSS) in default HTML error response.
**Learning:** The default error controller generated raw HTML incorporating the unescaped Exception message. In Crystal, `Exception#message` can be `nil` (`String?`), so safely interpolating it into HTML requires `HTML.escape(@ex.message || "")` and explicitly requiring the `"html"` module.
**Prevention:** Always escape user-controllable or dynamic string data, including exception messages, before interpolating it into an HTML template or string.
