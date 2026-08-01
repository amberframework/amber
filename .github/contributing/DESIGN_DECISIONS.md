# Design Decisions & Known Trade-offs

A living registry of **intentional** design decisions in Amber that look like bugs but are not. Reviewers should **discount** these — do not flag them as defects, and do not "fix" them in a PR without a separate, explicit discussion.

This file complements the [REVIEW_RUBRIC.md](REVIEW_RUBRIC.md), which owns the severity framework and per-type bars. This file owns the *context*: the deliberate choices the rubric assumes you already know.

## How to use it

- **Before flagging** something as a bug, missing default, or anti-pattern, scan this list for a matching entry. If it matches, it is by design — don't flag it.
- A finding that *contradicts* an entry here needs strong, specific evidence (a concrete reachable failure, a differential test). "Looks wrong" is not enough.
- If an entry is genuinely wrong or stale, that is a real change: open it as its own PR/discussion, update this file in the same PR, and link the reasoning. Don't silently regress a documented decision.

## How to add an entry

Add a new `###` section using the template at the bottom. Each entry has three parts:

1. **Decision** — what the code does, with the relevant repo-relative path.
2. **Rationale** — why it's that way.
3. **Don't flag** — the specific shapes of false-positive review comment this entry preempts.

Keep entries short and link to source. When you add an entry, you are saving every future reviewer the trip you just took.

---

## Entries

### App defaults live in the CLI app template, not framework core

- **Decision:** Default configuration and wired-up behavior for a *new app* live in the generated app template under `src/amber/cli/templates/app/...` (e.g. `config/routes.cr.ecr`, `config/application.cr.ecr`, `config/environments/`). Framework core ships the *capability*; the template ships the *default*.
- **Rationale:** Core stays unopinionated and embeddable. What a fresh `amber new` produces is the product surface where defaults belong, and where users can edit them.
- **Don't flag:** "Core doesn't set a sensible default for X" — that is often correct. Check the app template first. Conversely, a PR that adds a new pipe/feature but never wires it into `config/routes.cr.ecr` (or the relevant template file) has shipped inert dead code — *that* is worth flagging.

### crystal-db connection pool is already concurrency-safe

- **Decision:** Database access goes through `crystal-db`'s connection pool, which is concurrency-safe on its own.
- **Rationale:** The pool already manages checkout/checkin and fiber safety. Adding our own `Mutex` around it serializes what the pool deliberately parallelizes.
- **Don't flag:** "Database access isn't locked / needs a mutex / has a race." Do not re-add manual locking around pool checkout. If you think there's a real race, prove it sits *outside* the pool's guarantees.

### The dev error page and the bare HTML error page are two different paths

- **Decision:** The rich development error page is rendered by the `exception_page` shard. The hand-written HTML 500 page in `src/amber/controller/error.cr` is the **non-development** fallback only.
- **Rationale:** Development gets a detailed, interactive page from the shard; production gets a minimal, dependency-light page.
- **Don't flag:** Don't critique the dev page's markup/styling against `src/amber/controller/error.cr` — that file isn't what you see in development. Conversely, *do* scrutinize `error.cr` for the production threat model: it must escape any interpolated value (e.g. an `Exception#message` that can embed a request path) because that path is reflected to non-development users. Know which page you're looking at before commenting.

### Canonical shell-out is `Process.run(cmd, [args])`, no shell

- **Decision:** Shelling out uses `Process.run(cmd, [args])` with an argv array and **no shell**, not `system("string ...")` or `Process.run(string, shell: true)`. See the settled pattern in `src/amber/cli/commands/exec.cr` (e.g. `Process.run("cp", [_filename, @filename])`).
- **Rationale:** Passing an argv array avoids shell interpolation entirely, which sidesteps command injection from interpolated values.
- **Don't flag:** Existing `Process.run(cmd, [args])` calls as "should use a shell" — they shouldn't. *Do* flag any *new* `system("#{x} ...")` or `shell: true` with interpolated input, and steer it to the argv form.

### Non-clobbering header default idiom: `headers["X"] ||= value`

- **Decision:** When setting a default response (or request) header, the idiom is `headers["X"] ||= value`, which only sets it if the user hasn't (e.g. `request.headers["Content-Type"] ||= "..."` in `src/amber/cli/templates/app/spec/request_helper.cr.ecr`).
- **Rationale:** Defaults must not clobber values a user explicitly set. `||=` respects the caller's intent.
- **Don't flag:** "This header assignment is conditional / looks like it might not run." The `||=` is intentional. *Do* flag an unconditional `headers["X"] = value` that overwrites a user-supplied default header.

### Pipes are auto-required but inert until plugged into a pipeline

- **Decision:** `src/amber.cr` does `require "./amber/pipes/**"`, so every pipe file compiles and is available. But a pipe does **nothing** until it's added to a pipeline (typically in the app's `config/routes.cr.ecr` via `plug`).
- **Rationale:** Auto-require keeps pipes discoverable without manual `require` lists; pipeline wiring stays explicit and per-app so behavior is opt-in.
- **Don't flag:** "The pipe is auto-required, so it's active" — it isn't. "The pipe exists" ≠ "the pipe runs." A PR that adds a pipe must also wire it into the relevant pipeline/template to have any effect; an unplugged pipe is dead code, not a working feature.

### Single-source registries — don't hard-code duplicate lists

- **Decision:** Lists that can drift are defined once and referenced everywhere. The content-type / extension registry lives in `Content::TYPE` (`src/amber/controller/helpers/responders.cr`); even the extension regex is *derived* from it (`TYPE_EXT_REGEX = /\.(#{TYPE.keys.join("|")})$/`), and the router reuses that same constant.
- **Rationale:** One source of truth means adding/changing a type updates every consumer at once. Parallel hand-maintained lists silently diverge.
- **Don't flag:** Code that reads from `Content::TYPE` / `TYPE_EXT_REGEX` instead of inlining a literal list — that's the right move. *Do* flag a PR that introduces a *second*, hard-coded copy of an extension/content-type list that can drift from the registry.

### Crystal version policy: shard allows `>=1.0,<2`; CI pins 1.9.2 for specs

- **Decision:** `shard.yml` declares `crystal: ">= 1.0.0, < 2.0"`. CI runs the spec suite on `crystallang/crystal:1.9.2` (the lint/`ameba` job uses `:latest`).
- **Rationale:** Amber supports a broad Crystal range; specs are pinned to a known-good version for reproducible CI.
- **Don't flag:** Code that avoids newer-stdlib-only APIs or works around an older signature — that may be deliberate range support, not a missed modernization. Conversely, *do* flag a PR that relies on behavior or APIs only present in Crystal newer than 1.9.2 (it can pass local dev yet break CI/older users) — verify against the declared range, don't assume the newest stdlib.

---

## Template for new entries

Copy this block, fill it in, and place it in the **Entries** section.

```markdown
### <Short imperative title of the decision>

- **Decision:** <What the code does + repo-relative path(s), e.g. `src/amber/...`.>
- **Rationale:** <Why it's intentionally this way.>
- **Don't flag:** <The specific false-positive review comment(s) this preempts. Optionally: and DO flag <the real failure shape this is sometimes confused with>.>
```
