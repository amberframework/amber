---
name: review
description: Use when reviewing or triaging an Amber PR. Pulls the PR, checks mergeability mechanics, compiles and runs specs locally, classifies the PR type, applies the severity framework via the three discount levers (verifying claims rather than trusting the description), enforces the per-type correctness bar, discounts documented design trade-offs, decides enhancement vs feature, applies AI-PR hygiene, and produces a verdict (MERGE / MERGE_WITH_CHANGES / REQUEST_CHANGES / CLOSE) backed by file:line evidence.
---

# Reviewing an Amber PR

You are the maintainer. The rubric is the law: [REVIEW_RUBRIC.md](../../REVIEW_RUBRIC.md) is the single source of truth for the severity framework, per-type bars, and enhancement-vs-feature values; [DESIGN_DECISIONS.md](../../DESIGN_DECISIONS.md) lists intentional trade-offs you must discount. This skill is only the *procedure* — it does not restate the rubric.

Golden rule: **the PR description is a claim, not evidence.** Verify everything against the diff and against running code. Cite `file:line` for every point you make.

## 1. Pull the PR and check mergeability mechanics

```sh
gh pr checkout <number>
gh pr view <number> --json title,author,body,files,additions,deletions
gh pr view <number> --json mergeable,mergeStateStatus,reviewDecision
gh pr diff <number>
```

Read the mechanics before you read the code (see rubric §6):

- `mergeable: CONFLICTING` -> not reviewable yet; ask for a rebase.
- `mergeStateStatus: BLOCKED` -> usually a required review/approval, **not** a merge conflict. Check `reviewDecision`; do not chase a phantom conflict.
- `reviewDecision: REVIEW_REQUIRED` / `CHANGES_REQUESTED` -> exactly that.
- Skim the diff once end-to-end now. Note its true scope (does it match the title?) before forming opinions.

## 2. Compile and run specs locally

A PR with red specs or `bin/ameba` errors gets bounced, not reviewed (rubric §6, §7). Match CI before spending review attention:

```sh
shards install        # produces bin/ameba
bin/amber_spec        # ./bin/ameba, crystal tool format --check, crystal spec, crystal spec ./spec/build_spec_granite.cr
```

- The granite spec needs a local Postgres (DB `granite_test`, user `postgres`, password `postgres`); start one or note it as not-run.
- CI pins **Crystal 1.9.2** for specs. If it's green for you on a newer compiler, suspect a version-pin break and re-check against the declared range (`>= 1.0.0, < 2.0`).
- **Green specs do not mean correct.** If the suite is happy-path only, green tells you nothing about the edge cases the change can break (§3 Performance). Hold that thought for step 5.

## 3. Classify the PR type

Pick exactly one type and review against *that* bar (rubric §3): **Bugfix · Security · Performance · Refactor · Feature/default-change.** State your choice in the review. If the author claimed a type, confirm the diff actually fits it — a "refactor" that edits spec *assertions* is not a refactor; a "perf" change that alters output is a behavior change.

## 4. Apply the severity framework — verify, then discount

For every issue you raise, assign a tier (Critical / High / Medium / Low / Informational per rubric §2), then **discount it** through the three levers. A raw finding is a hypothesis; the surviving severity is what you report. **Verify each lever yourself in the diff/code — do not inherit the author's framing.**

- **(a) Reachability + existing mitigations.** Trace the finding to a sink an attacker can actually drive, then check for `rescue` on the immediate caller and a top-level `Pipe::Error`/framework handler before assigning severity. Worked example: the `MessageVerifier`/`MessageEncryptor` `IndexError` "DoS" was fully contained by `SignedStore#verify`, `EncryptedStore#verify_and_decrypt`, and `Pipe::Error` -> Informational/Low, not High. If a mitigation exists, name it and discount.
- **(b) Threat model.** Network-facing vs local dev CLI. A `bin/amber`/CLI command already runs as the operator, so the `encrypt.cr` `system("#{ed} #{file}")` injection is **Low** (operator is the attacker). The same shape on a network endpoint jumps several tiers.
- **(c) Environment gating.** Where does the dangerous branch run? The `error.cr` unescaped `@ex.message` is in the **non-development** branch, so it's a production reflected-XSS (High); a finding that only fires in `development?` is usually Low/Informational because production never executes it.

Do not accept a severity from the description. Re-derive it from the three levers, citing the lines.

## 5. Apply the per-type correctness bar

Grade the diff against the bar for the type you picked in step 3 (rubric §3). The bar is **evidence**, not vibes:

- **Bugfix:** a spec that was red before the fix and is green now; root-cause not symptom; blast-radius note.
- **Security:** clears all of §3 Security — real+reachable+not-already-mitigated; **complete** fix (the `encrypt.cr` fix that escaped the file but left `$EDITOR` injectable failed this — prefer eliminating the shell via `Process.run(cmd, [args])`); **narrow** fix (no over-broad `rescue`, no loosened auth check); an **adversarial spec** that sends the malicious input and asserts neutralization.
- **Performance:** **provably behavior-identical.** Require the differential edge-case table (dotfiles, trailing slash, empty/extension-only segments) — this is exactly where the `File.extname` router PR diverged while CI stayed green. No table, no merge.
- **Refactor:** existing suite passes **unchanged**; if assertions were edited, it's not a pure refactor — reclassify.
- **Feature/default-change:** tests for the new behavior and its edge cases; docs/changelog updated; description matches code; extra scrutiny per step 7.

## 6. Discount documented design trade-offs

Before you flag anything that smells like "why is it done this way," scan [DESIGN_DECISIONS.md](../../DESIGN_DECISIONS.md). If an entry matches, it is **by design** — do not flag it, and reject a PR that "fixes" it without a separate discussion. Common ones the wave tripped on:

- App defaults live in the **CLI app template**, not core — so "core has no default for X" is often correct, and a pipe not wired into `config/routes.cr.ecr` is dead code.
- `crystal-db`'s pool is already concurrency-safe — don't accept a re-added `Mutex` around checkout.
- `error.cr` is the **non-development** page (dev uses the `exception_page` shard) — review it for the production threat model, not its markup.
- `Process.run(cmd, [args])` (no shell) is the settled shell-out idiom; `headers["X"] ||= value` is the intentional non-clobbering default.
- Extension/content-type lists derive from `Content::TYPE` / `TYPE_EXT_REGEX` — a hand-coded duplicate that can drift *is* flaggable.

A finding that contradicts an entry needs strong specific evidence (a concrete reachable failure or differential test), not "looks wrong."

## 7. Decide enhancement vs feature

Apply the rubric §4 values:

- **Enhancement** (improves something Amber already does without changing its surface contract) -> review against its matching §3 type bar plus evidence it doesn't change behavior for existing apps. Welcome as a PR.
- **New feature** (new pipe / CLI command / config knob / template default) -> Feature/default-change bar **plus design buy-in**; it should usually have started as an issue/discussion. A drive-by feature PR with no prior agreement is a reason to ask for that discussion first.
- **Default/behavior changes get extra scrutiny.** They change every app silently on upgrade — recall the SecureHeaders PR that shipped HSTS on-by-default (can hard-break HTTP) *and* was inert dead code. Confirm the **semver** call-out in the PR: a default/behavior change is **not** patch-safe (minor at minimum, major if it can break existing requests).

## 8. Apply AI-PR hygiene

AI-assisted PRs are welcome (rubric §5) — hold them to the same checklist:

- [ ] **Description matches the code** — grep the diff against the claims; mismatch is the single most common wave failure.
- [ ] **One concern, scoped diff** — no security-fix-plus-refactor-plus-rename bundles.
- [ ] **Edge-case tests present** — dotfiles, empty/trailing segments, malformed input, non-development env.
- [ ] **No duplication** — check against recently merged PRs; assistants re-propose already-settled patterns (e.g. the `Process.run` no-shell fix).
- [ ] **Learning notes accurate and clean** — `.jules/*`-style notes are fine if correct and contain nothing machine-specific (no absolute local paths, hostnames, usernames, tokens, env dumps).

## 9. Produce the verdict

End with one verdict and the evidence behind it. Every claim cites `file:line`.

- **MERGE** — fits its type bar, levers leave no live high/critical, no design-decision conflict, mechanics clean. Say what you verified.
- **MERGE_WITH_CHANGES** — sound and mergeable after small, named fixes (e.g. add the one missing adversarial spec, wire the pipe into `config/routes.cr.ecr`, drop the machine-specific note). List each required change with its `file:line`.
- **REQUEST_CHANGES** — fails a bar or a lever in a way that needs author rework (incomplete security fix, missing differential table, over-broad `rescue`, description/code mismatch). State the bar it missed and what evidence would clear it.
- **CLOSE** — wrong by design (contradicts a DESIGN_DECISIONS entry without evidence), a non-issue after discounting (the "DoS" that was fully mitigated), a duplicate of settled work, or a feature with no design buy-in that belongs in a discussion. Point to the rubric/decision that settles it.

Verdict template:

```
Type: <Bugfix|Security|Performance|Refactor|Feature/default-change>
Mergeability: mergeable=<...> mergeStateStatus=<...> reviewDecision=<...>
Local checks: bin/amber_spec <pass|fail|granite not-run>
Findings:
  - [<Critical|High|Medium|Low|Informational>] <one line> (file:line) — levers applied: <a/b/c result>
Design-decision discounts: <entry or none>
Enhancement vs feature: <which, + semver note if default/behavior change>
AI hygiene: <pass | list gaps>
Verdict: <MERGE|MERGE_WITH_CHANGES|REQUEST_CHANGES|CLOSE>
Required to clear: <named changes with file:line, or n/a>
```
