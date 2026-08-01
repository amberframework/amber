# Amber Review Rubric

The canonical, single source of truth for how we judge a change to Amber. Everything else (the pre-review skill, the review skill, the PR template, `.github/CONTRIBUTING.md`) links here and adds only its own lens. If those documents and this one ever disagree, **this document wins** — fix the other.

## 1. Purpose & how to use

Multiple AI coding assistants now open PRs against Amber. A 2026-06-15 wave surfaced a small set of repeatable failure shapes (over-stated severities, incomplete fixes, "perf" changes that quietly altered behavior, dead/dangerous defaults). This rubric exists so both sides catch them before they cost review cycles.

- **Contributors — run this before opening a PR.** Load the pre-review skill (`.github/contributing/skills/pre-review/SKILL.md`), self-grade against this rubric, fix what you find, and fill the PR template honestly. The cheapest review note is the one you never trigger.
- **Maintainers — run this before merging.** Load the review skill (`.github/contributing/skills/review/SKILL.md`) and grade the diff against the matching PR-type bar (§3), apply the discount levers (§2) before you assign a severity, and verify mergeability (§6) plus local/CI checks (§7).

Use second person, cite the actual file and line, and prefer "here is the reachable sink" over "this looks scary."

## 2. Severity framework — "what is important"

Assign a tier to every issue you raise. Then **discount it** with the three levers below. A raw finding is a hypothesis; the severity is what survives the levers.

### Tiers

| Tier | Meaning | Concrete Amber example (2026-06-15 wave) |
|---|---|---|
| **Critical** | Remote, unauthenticated, no preconditions: RCE, auth bypass, secret/data disclosure at scale. | (None confirmed in the wave — reserve this tier; it triggers an immediate fix/release, not a normal review.) |
| **High** | Real exploit with realistic preconditions, or in a default-on/network-facing path. | Reflected XSS: `src/amber/controller/error.cr` interpolates an unescaped `@ex.message` into the HTML 500 page (`RouteNotFound` embeds the request path). Network-facing — **but see Environment gating below**, which is why it lands High, not Critical. |
| **Medium** | Exploitable only with significant preconditions, or limited blast radius, or needs an unusual config. | A malformed-cookie code path that raises an unexpected exception type and produces a confusing 500, where the request is already authenticated/contained. |
| **Low** | Real but minor: needs local access, the operator is the attacker, or impact is cosmetic/hardening. | Command injection in `src/amber/cli/commands/encrypt.cr` — `system("#{options.editor} #{unencrypted_file}")` runs a shell. Real, but it is a **local dev CLI**: the operator already controls `$EDITOR` and the filesystem. |
| **Informational** | Style, naming, doc nits, defense-in-depth suggestions with no live vector. | "Consider escaping here too even though this branch is dev-only." Note it; do not block on it. |

### The three discount levers (apply before finalizing severity)

**(a) Reachability — is there a real attacker-reachable sink, and is it already mitigated?**
Trace the finding to a sink an attacker can actually drive, *then* check existing mitigations on the path before you assign severity.
- Worked example (the "DoS" that was not one): `MessageVerifier` / `MessageEncryptor` raise `IndexError` on malformed cookies. Sounds like a DoS — but every attacker-reachable caller already rescues it (`SignedStore#verify`, `EncryptedStore#verify_and_decrypt`), and the top-level `Pipe::Error` catches the rest. Reachable sink with full existing mitigation -> **downgrade to Informational/Low**, not High.
- Checklist: Can an unauthenticated request reach it? Does the immediate caller `rescue`? Is there a top-level `Pipe::Error` (or framework handler) that already contains it? If yes, say so explicitly and discount.

**(b) Threat model — local dev CLI vs network-facing.**
Who is the attacker relative to who already has control? A network endpoint trusts no one; a `bin/amber`/CLI command already runs as the operator.
- The `encrypt.cr` command injection is real code-smell but **Low**, because the person who can set `$EDITOR` and write the YAML file is the same person the shell would run as. Network-facing equivalents jump several tiers.

**(c) Environment gating — production vs development-only.**
Where the dangerous branch only executes outside `development`, severity rises in prod and the dev path is fine — and vice versa.
- The `error.cr` XSS lives in the non-development branch (`else "<html>...<pre>#{@ex.message}</pre>..."`); the development branch renders the safe `Amber::Exceptions::Page`. So it is a **production** bug (High), not a dev annoyance. Gating can cut both ways: a finding that only fires in `development?` is usually Low/Informational because production never runs it.

## 3. Correctness bars by PR type

Pick the type that matches the change. State which one you are reviewing/submitting against. The bar is **evidence**, not vibes.

### Bugfix
- A failing spec that **reproduces the bug** (red before the fix), now green.
- The fix targets the root cause, not the symptom; no unrelated drive-by edits.
- A note on blast radius: what else calls this path?

### Security
A security PR must clear **all** of:
- **Real + reachable + not-already-mitigated.** Apply §2(a)–(c). If a top-level `Pipe::Error` or caller `rescue` already contains it, say why your fix still matters.
- **Complete fix — no leftover vector.** Counter-example from the wave: the proposed `encrypt.cr` fix escaped the *file* but left the *editor* injectable, so the shell vector survived. The repo already settled the correct pattern in `exec.cr`: `Process.run(cmd, [args])` (no shell) — prefer eliminating the shell over escaping.
- **Narrow fix — no over-broad rescue or auth bypass.** Do not wrap a wide block in `rescue` (it hides unrelated failures) and do not loosen an auth/verification check to make the symptom disappear.
- **Adversarial spec.** A spec that sends the malicious input (the XSS payload, the malformed cookie, the injected `$EDITOR`) and asserts it is neutralized — not just that the happy path still works.

### Performance
Perf changes are the highest-risk "looks fine" category. A perf PR must be **provably behavior-identical**.
- **Differential edge-case table required.** Enumerate inputs where the old and new implementation could diverge and show they agree. Template:

  | Input | Old behavior | New behavior | Same? |
  |---|---|---|---|
  | normal path `/users/1` | route key `users/1` | route key `users/1` | yes |
  | dotfile `/.well-known/x` | ... | ... | **must verify** |
  | trailing slash `/users/` | ... | ... | **must verify** |
  | extension-only / empty segment | ... | ... | **must verify** |

  Worked example (the wave): a PR replaced an anchored regex with `File.extname` in the router. **Not** semantically identical — dotfiles and trailing-slash inputs diverge, building a corrupted route key. CI stayed green because the specs were happy-path only.
- **"Green specs != correct."** If the existing suite only covers the happy path, green tells you nothing about the edge cases. Add the differential specs that exercise the divergent inputs.
- A benchmark (before/after numbers, method, hardware) justifying the change is worth making at all.

### Refactor
- **Behavior-preserving by definition.** The existing suite must pass unchanged; if you had to edit a spec's *assertions*, it is not a pure refactor — re-file it.
- No public API or default changes ride along (those are Feature/default-change).
- If behavior could subtly shift, add the differential specs from the Performance bar.

### Feature / default-change
- Tests for the new behavior **and** its edge cases.
- Docs/changelog updated; the PR description matches what the code does (§5).
- **Default/behavior changes get extra scrutiny — see §4.** New default middleware, a changed pipeline, a new on-by-default header all change every existing app on upgrade.

## 4. Enhancement vs new feature (our values)

- **Enhancement** = improves something Amber already does (faster, clearer error, better default ergonomics) without changing the framework's surface contract. **Bar:** the matching §3 type bar (usually Bugfix/Refactor/Performance) plus evidence it does not change behavior for existing apps. Welcome as a PR.
- **New feature** = adds surface area (new pipe, new CLI command, new config knob, new template default). **Bar:** the Feature/default-change bar, *plus* design buy-in. A new feature should usually **start as an issue or discussion**, not a drive-by PR — so we agree it belongs in core before you build it.

**Why default/behavior changes get extra scrutiny (and a semver note):**
- They affect every app on upgrade, silently. Worked example (the wave): a SecureHeaders pipe PR added a pipe but never plugged it into the app template (`config/routes.cr.ecr` in the generated app) -> **inert dead code**; and it shipped **HSTS on-by-default**, which can hard-break HTTP for real sites. App defaults belong in the **CLI app template**, not bolted onto an existing app's runtime, and "on by default" needs an explicit safety argument.
- **Semver:** a new default/behavior change is **not patch-safe**. Changing a default or pipeline is a **minor** at minimum (new behavior) and a **major** if it can break an existing app's requests. Call out the bump in the PR.

## 5. AI-assisted contributions

AI-assisted PRs are **welcome and encouraged** — this whole rubric assumes them. The expectations:

- [ ] **Description matches the code.** The PR text describes what the diff *actually does*, not what the assistant intended. Mismatch is the single most common wave failure — reviewers should grep the diff against the claims.
- [ ] **One concern per PR, scoped diff.** No bundling a security fix with a refactor with a rename. Small diffs review faster and revert cleaner.
- [ ] **Tests including the edge cases assistants tend to skip.** Dotfiles, empty/trailing segments, malformed input, non-development env — the exact spots where "green happy-path specs" hide divergence (§3 Performance).
- [ ] **No duplication.** Check the change against recently merged PRs before opening; assistants frequently re-propose something already landed or already settled (e.g. the `Process.run` no-shell pattern in `exec.cr`).
- [ ] **Learning notes welcome if accurate.** `.jules/*`-style notes are fine to include when they are correct and contain **nothing machine-specific** (no absolute local paths, hostnames, usernames, tokens, or env dumps).

## 6. Mergeability mechanics

Before review, confirm the PR can actually merge:

```sh
gh pr view <number> --json mergeable,mergeStateStatus,reviewDecision
```

- `mergeable: CONFLICTING` -> rebase/resolve; not reviewable yet.
- `mergeStateStatus: BLOCKED` -> **usually a required review/approval, not a merge conflict.** Do not chase a phantom conflict; check `reviewDecision`.
- `reviewDecision: REVIEW_REQUIRED` / `CHANGES_REQUESTED` -> exactly what it says.
- **Local checks must pass before a human spends review time.** A PR with failing `bin/ameba` or red specs gets bounced back, not reviewed (§7).

## 7. Running the checks locally to match CI

CI is **CircleCI** (`.circleci/config.yml`). Every PR runs three jobs — match them locally before you push:

1. **ameba-test** (lint; image `crystallang/crystal:latest`):
   ```sh
   shards install   # produces bin/ameba (dev dependency, ~> 1.5.0)
   bin/ameba
   ```
2. **amber-specs** (full suite; image `crystallang/crystal:1.9.2`; **no database services**):
   ```sh
   crystal spec
   ```
   CI pins **Crystal 1.9.2** for specs (shard.yml allows `>= 1.0.0, < 2.0`); if it passes for you on a newer compiler but fails in CI, suspect the version pin.
3. **granite-test** (`crystal spec spec/build_spec_granite.cr`; **needs a postgres service**):
   ```sh
   crystal spec ./spec/build_spec_granite.cr
   ```
   Requires a reachable Postgres with DB `granite_test`, user `postgres`, password `postgres`. Without it, this spec cannot pass — start a local Postgres first.

(The `osx_tests` job runs only for a manually triggered pre-release, not per PR.)

**Shortcuts (use these, don't reinvent them):**
- `bin/amber_spec` runs all four checks in order: `./bin/ameba`, `crystal tool format --check`, `crystal spec`, `crystal spec ./spec/build_spec_granite.cr`. Run it before every push.
- The git hooks in `.githooks/` (installed via `bin/setup-dev`) run the fast checks automatically on commit/push so you catch failures before CI does.

## 8. See also

- **`.github/contributing/DESIGN_DECISIONS.md`** — deliberate trade-offs in Amber that reviewers should **discount** (do not flag a settled decision as a bug). Read it before raising a finding that smells like "why is it done this way."
