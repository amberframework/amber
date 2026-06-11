# Agent Guidelines & Project Cooperation Protocol

This document outlines the protocols, coding conventions, testing rules, and commit message standards for AI agents cooperating on the Amber Framework.

---

## 1. Project Journaling Protocol (PJP)
All agent sessions must maintain a concurrency-safe, LLM-efficient project memory using the `ajourn` tool.
* **Startup**: Run `ajourn startup` as the very first step of any session.
* **Persistence**: Log "Knowledge Deltas" using `ajourn log -m "..." -t "..."`.
* **Standard Tags/Vocabulary**:
  * `DEC` (Decision): Architectural, design, or procedural decisions.
  * `RAT` (Rationale): Explanations for specific code patterns, fixes, or designs.
  * `GOT` (Gotchas): Non-obvious quirks of the codebase, compilers, or platform.
  * `PRB` (Problems): Blockers, failing specs, or compilation errors.
  * `USR` (User Requests): Directly mapped requirements or constraints from the user.

---

## 2. Coding Conventions & Quality Guidelines

* **FHS & Safety**: Avoid direct modifications to system files unless necessary. Keep dependencies scoped within `shard.yml`.
* **Fail Fast**: Check preconditions early in functions; return or raise early on invalid states.
* **Strict Typing**: Rigorously leverage the Crystal type system. Avoid generic `Any`/`Object` where possible.
* **Formatting**: Format all codebase changes using `crystal tool format` before committing.
* **No Nil Assertions**: Do not use `.not_nil!` unless absolutely necessary. Handle `nil` conditions safely using conditional blocks (`if`, `unless`) or rescue/fallback blocks.

---

## 3. Spec & Testing Guidelines

* **Location**: All tests must reside in the `./spec` folder.
* **Structure**:
  * Treat `describe` as a noun or situation (e.g., `describe HTTP::Request`).
  * Treat `it` as a statement about state or how an operation changes state (e.g., `it "returns the parsed URL"`).
* **Test Isolation**: Ensure specs run fast, run locally, and do not introduce cross-test state leakage.
* **Mocking & Services**: Ensure external dependencies (like Redis) are properly configured or stubbed.

---

## 4. Git Commit Standards

Commits must match the template specified in `.gitmessage` and include explicit AI attribution headers:
* **Format**:
  ```text
  Commit Title Here Eg. Redirect user to the requested page after login

  Issue: Add relevant links to issue/story/card and any other important references

  # Why is this change necessary?
  * [Explanation]

  # How does it address the issue
  * [Explanation]

  # What side effects does this change have?
  * [Explanation]

  Co-developed-by: Gemini AI <renich+gemini@woralelandia.com>
  Signed-off-by: Rénich Bon Ćirić <renich@woralelandia.com>
  ```
