# Contributor review infrastructure

This folder holds the shared review docs and skills for Amber. They exist because multiple AI coding assistants now open PRs, and a recurring set of failure shapes (reflected XSS, "vulnerabilities" with no reachable sink, incomplete fixes, inert dead code, perf changes that silently alter behavior) need to be caught before merge — by contributors self-reviewing and by maintainers reviewing.

## What's in here

| File | What it is |
| --- | --- |
| [REVIEW_RUBRIC.md](./REVIEW_RUBRIC.md) | The source of truth: severity framework, per-change-type quality bars, and how we value enhancements vs. new features. Everything else links here instead of duplicating it. |
| [DESIGN_DECISIONS.md](./DESIGN_DECISIONS.md) | Deliberate trade-offs reviewers should DISCOUNT — settled decisions, so you don't re-flag them as bugs. |
| [skills/pre-review/SKILL.md](./skills/pre-review/SKILL.md) | Contributor skill. Self-review your own change against the rubric before you push. |
| [skills/review/SKILL.md](./skills/review/SKILL.md) | Maintainer skill. Review an incoming PR against the rubric. |

## Loading the skills

The skills are intentionally **not committed under `.claude/`** and are **not auto-loaded** — they live here, version-controlled with the code they describe. To make your assistant pick them up, link or copy them into your personal `.claude/skills/`:

* **Recommended:** run `bin/setup-dev` once from the repo root. It installs the local git hooks and symlinks the skills into `.claude/skills/`.
* **Manual:** symlink (or copy) each skill folder into your `.claude/skills/`, for example:

  ```sh
  mkdir -p .claude/skills
  ln -s ../../.github/contributing/skills/pre-review .claude/skills/pre-review
  ln -s ../../.github/contributing/skills/review .claude/skills/review
  ```

`.claude/` is gitignored, so these links stay local to your checkout and are never committed.

## Running the checks (match CI)

CI is CircleCI (`.circleci/config.yml`). Every change runs three jobs:

1. **ameba-test** — `shards install` then `bin/ameba` (lint).
2. **amber-specs** — `shards install` then `crystal spec` (full suite, **Crystal 1.9.2**, no database services).
3. **granite-test** — `shards install` then `crystal spec spec/build_spec_granite.cr` (needs a **PostgreSQL** service: DB `granite_test`, user `postgres`, password `postgres`).

To reproduce all of it locally in one shot, run the existing script from the repo root:

```sh
bin/amber_spec
```

It runs `bin/ameba`, `crystal tool format --check`, `crystal spec`, and `crystal spec ./spec/build_spec_granite.cr`. The Granite build spec needs a local PostgreSQL running; CI pins Crystal 1.9.2 for the spec suite, so if you see version-specific failures, test against 1.9.2.

## Where to start

Read [REVIEW_RUBRIC.md](./REVIEW_RUBRIC.md) first, then skim [DESIGN_DECISIONS.md](./DESIGN_DECISIONS.md) so you don't re-litigate settled trade-offs.
