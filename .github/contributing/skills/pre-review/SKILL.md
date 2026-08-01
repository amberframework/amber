---
name: pre-review
description: Self-review checklist to run BEFORE opening or updating a PR against Amber. Use it whenever you (or an AI assistant) are about to push a branch and open or refresh a pull request — it grades your own change against the Amber Review Rubric so CI is green and a maintainer's first pass finds nothing avoidable. Use when about to open a PR, update an existing PR, or check whether a change is ready to submit.
---

# Pre-review: grade your own PR before a maintainer does

You are about to open or update a PR against Amber. Run this procedure first. The
cheapest review note is the one you never trigger. The rubric below is the source
of truth — this skill is just the contributor lens on it.

- Severity framework, per-type bars, enhancement-vs-feature values: **[REVIEW_RUBRIC.md](../../REVIEW_RUBRIC.md)** (canonical — do not duplicate it here).
- Intentional trade-offs you should NOT "fix": **[DESIGN_DECISIONS.md](../../DESIGN_DECISIONS.md)**. Scan it before touching anything that looks like a bug — you may be undoing a settled decision.

Work the steps in order. Don't skip a checkbox because it "looks obvious" — that
is exactly where the 2026-06-15 wave failed.

## 1. Classify your PR type

Pick exactly one and write it in the PR description. The type sets your bar (rubric §3).

- [ ] **Bugfix** — fixes incorrect behavior.
- [ ] **Security** — closes a real, reachable vulnerability.
- [ ] **Performance** — same behavior, faster.
- [ ] **Refactor** — same behavior, cleaner code.
- [ ] **Feature / default-change** — new surface area or a changed default/pipeline/header.

If it's an **enhancement vs a new feature**, decide which (rubric §4). A *new feature*
(new pipe, CLI command, config knob, template default) should usually **start as an
issue/discussion** for design buy-in before you build it — not a drive-by PR.

## 2. Make the description match the code

This is the single most common wave failure: the PR text describes intent, not the diff.

- [ ] Read your own `git diff` and write the description from what the code **actually does**.
- [ ] Grep your claims against the diff — every "fixes X", "adds Y", "no behavior change"
      must be visible in the changed lines.
- [ ] Remove aspirational language ("should", "intended to") for things the code doesn't do.

## 3. One concern, minimal diff

- [ ] Exactly one concern. No bundling a security fix with a refactor with a rename.
- [ ] No unrelated drive-by edits, reformatting of untouched code, or dependency bumps.
- [ ] Smaller is better — small diffs review faster and revert cleaner.

## 4. Meet your per-type bar (rubric §3)

State which bar you're submitting against, then clear it with **evidence, not vibes**.

**Bugfix** — a spec that's **red before the fix, green after**; fix the root cause, not the symptom; note what else calls this path.

**Refactor** — the existing suite passes **unchanged**. If you had to edit a spec's
*assertions*, it is not a pure refactor — reclassify it. No public-API/default changes ride along.

**Performance** — perf is the highest-risk "looks fine" category. You must prove it's
**behavior-identical**. Fill in a differential edge-case table in the PR description and
verify each row with a real spec — green happy-path specs tell you nothing about edges:

| Input | Old behavior | New behavior | Same? |
|---|---|---|---|
| normal path `/users/1` | route key `users/1` | route key `users/1` | yes |
| dotfile `/.well-known/x` | … | … | **must verify** |
| trailing slash `/users/` | … | … | **must verify** |
| empty / extension-only segment | … | … | **must verify** |

(The wave's perf PR swapped an anchored regex for `File.extname`; dotfiles and trailing
slashes diverged and built a corrupted route key, but CI stayed green on happy-path specs.)
Include a before/after benchmark (method + hardware) justifying the change.

**Security** — clear **all** of these and write an **honest severity self-assessment**
using the three levers (rubric §2): **(a) reachability** — name the real
attacker-reachable sink AND state whether a caller `rescue` or top-level `Pipe::Error`
already mitigates it; **(b) threat model** — local dev CLI (operator is the attacker → Low)
vs network-facing; **(c) environment gating** — production path vs `development?`-only.
Don't over-state: the wave's "DoS" was already rescued at every reachable caller, and the
`encrypt.cr` command injection was a **Low** local-CLI issue.

- [ ] Real + reachable + not-already-mitigated (apply levers a–c above).
- [ ] **Complete fix** — no leftover vector. Prefer eliminating the shell
      (`Process.run(cmd, [args])`, the settled `exec.cr` pattern) over escaping one input.
- [ ] **Narrow fix** — no over-broad `rescue` hiding unrelated failures, no loosened auth check.
- [ ] **Adversarial spec** — send the actual malicious input (XSS payload, malformed cookie,
      injected `$EDITOR`) and assert it's neutralized, not just that the happy path still works.

**Feature / default-change** — tests for the new behavior **and** its edges; docs/changelog
updated. Default/behavior changes get extra scrutiny (rubric §4): they hit every app on
upgrade. App defaults belong in the **CLI app template** (e.g. `config/routes.cr.ecr`), not
bolted onto core; a new pipe must be **plugged into a pipeline** or it's inert dead code; and
"on by default" needs an explicit safety argument (the wave shipped HSTS-on-by-default — dangerous).
- [ ] Note the **semver** impact: a default/pipeline change is **minor** at minimum, **major** if it can break an existing app's requests.

## 5. Add tests, including the edge cases assistants skip

- [ ] New/changed behavior is covered by a spec.
- [ ] Edge cases the wave hid in: dotfiles, empty/trailing segments, malformed input,
      and the **non-development** branch (production-only code paths).
- [ ] For perf/refactor, the **differential** specs that exercise the divergent inputs from your §4 table.

## 6. Don't duplicate a recently-merged PR

- [ ] Check open/recently-merged PRs first — assistants frequently re-propose something
      already landed or already settled:
      ```sh
      gh pr list --state merged --limit 30
      gh pr list --state open --search "<keyword from your change>"
      ```
- [ ] Confirm you're not re-introducing a pattern the repo already settled (e.g. the
      `Process.run` no-shell idiom) or contradicting a [DESIGN_DECISIONS.md](../../DESIGN_DECISIONS.md) entry.
- [ ] If you include `.jules/`-style learning notes, make sure they're accurate and contain
      **nothing machine-specific** (no absolute local paths, hostnames, usernames, tokens, env dumps).

## 7. Run the local checks so CI is green the first time

CI is CircleCI and runs lint + the full spec suite + the postgres-backed granite build spec
on every PR (rubric §7). Match it locally **before** you push.

- [ ] One-time setup (idempotent — installs git hooks + makes the skills loadable):
      ```sh
      shards install   # produces bin/ameba
      bin/setup-dev
      ```
- [ ] Run the full CI-matching check — lint, format, specs, and the granite build spec:
      ```sh
      bin/amber_spec
      ```
      (The granite spec needs a local Postgres: DB `granite_test`, user `postgres`, password `postgres`.)
- [ ] Let the hooks installed by `bin/setup-dev` do their job — **pre-commit** runs the fast
      `crystal tool format --check`, **pre-push** runs format + `bin/ameba` + `crystal spec`.
      If a hook fails, fix the cause; don't reach for `SKIP_HOOKS=1`.
- [ ] CI pins **Crystal 1.9.2** for specs (shard allows `>= 1.0.0, < 2.0`). If it passes on a
      newer compiler for you but you suspect the pin, verify against 1.9.2 — don't rely on
      newer-stdlib-only APIs.

## Final gate

- [ ] PR type stated, description matches the diff, one concern, per-type bar met with evidence,
      tests + edge cases, no duplication, `bin/amber_spec` green. Now fill in the PR template honestly and open it.
