# Amber LSP — Claude Code Integration Guide

The Amber LSP is a diagnostics-only language server that checks your Crystal code against Amber framework conventions. It works with Claude Code to catch mistakes automatically as files are edited.

## Quick Start

### 1. Build the LSP binary

```bash
cd path/to/amber_cli
crystal build src/amber_lsp.cr -o bin/amber-lsp --release
```

The `amber_cli` repository is at https://github.com/amberframework/amber_cli.

### 2. Set up your project

From your Amber application directory, run:

```bash
amber setup:lsp
```

This creates three files:

| File | Purpose |
|------|---------|
| `.lsp.json` | Tells Claude Code where the LSP binary is and what files it handles |
| `.claude-plugin/plugin.json` | Plugin manifest so Claude Code discovers the LSP |
| `.amber-lsp.yml` | Rule configuration — customize severity, disable rules, add custom rules |

### 3. Start Claude Code

That's it. Open Claude Code in your project directory and the LSP activates automatically.

---

## Manual Setup (Without CLI)

If you prefer to set things up by hand or the CLI command isn't available:

### `.lsp.json` (project root)

```json
{
  "amber": {
    "command": "/full/path/to/bin/amber-lsp",
    "args": [],
    "extensionToLanguage": {
      ".cr": "crystal"
    },
    "transport": "stdio",
    "restartOnCrash": true,
    "maxRestarts": 3
  }
}
```

Replace `/full/path/to/bin/amber-lsp` with the actual absolute path to your compiled binary.

### `.claude-plugin/plugin.json`

```json
{
  "name": "amber-framework-lsp",
  "version": "1.0.0",
  "description": "Convention diagnostics for Amber V2 web framework projects.",
  "author": { "name": "Amber Framework" },
  "lspServers": "./.lsp.json"
}
```

---

## What the LSP Checks

The LSP ships with 15 built-in convention rules:

| Rule | Severity | What It Checks |
|------|----------|----------------|
| `amber/controller-naming` | Error | Controller classes must end with `Controller` |
| `amber/controller-inheritance` | Error | Must inherit from `ApplicationController` or `Amber::Controller::Base` |
| `amber/action-return-type` | Warning | Actions should call `render`, `redirect_to`, or `respond_with` |
| `amber/filter-syntax` | Error | Detects Rails-style `before_action :symbol` and deprecated `before_filter` |
| `amber/job-perform` | Error | Job classes must define a `perform` method |
| `amber/job-serializable` | Warning | Jobs should include `JSON::Serializable` |
| `amber/channel-handle-message` | Error | Channels must define `handle_message` |
| `amber/pipe-call-next` | Error | Pipes overriding `call` must invoke `call_next` |
| `amber/spec-existence` | Info | Controllers should have a corresponding spec file |
| `amber/route-controller-exists` | Warning | Controllers referenced in routes should exist as files |
| `amber/schema-field-type` | Error | Schema field types must be valid Crystal types |
| `amber/mailer-methods` | Error | Mailers must define `html_body` and `text_body` |
| `amber/file-naming` | Warning | Crystal files must be snake_case |
| `amber/directory-structure` | Warning | Classes should be in their expected directories |
| `amber/socket-channel-macro` | Warning | ClientSockets should define at least one `channel` |

---

## Configuration

### `.amber-lsp.yml`

Place this file in your project root to customize behavior.

#### Disable a rule

```yaml
rules:
  amber/spec-existence:
    enabled: false
```

#### Change severity

```yaml
rules:
  amber/spec-existence:
    severity: hint
  amber/file-naming:
    severity: error
```

Valid severities: `error`, `warning`, `information`, `hint`

#### Exclude directories

```yaml
exclude:
  - lib/
  - tmp/
  - db/migrations/
  - vendor/
```

---

## Custom Rules

You can define project-specific rules using regex patterns in `.amber-lsp.yml`. No recompilation needed.

### Basic pattern rule

Flag `puts` statements in production code:

```yaml
custom_rules:
  - id: "project/no-puts"
    description: "Do not use puts in production code"
    severity: warning
    applies_to: ["src/**"]
    pattern: "^\\s*puts\\b"
    message: "Avoid 'puts' in production code. Use Log.info instead."
```

### Negated rule (require something exists)

Require a copyright header in every file:

```yaml
custom_rules:
  - id: "project/require-copyright"
    description: "Every source file must have a copyright header"
    severity: info
    applies_to: ["src/**"]
    pattern: "^# Copyright"
    negate: true
    message: "Missing copyright header."
```

When `negate: true`, the rule reports a diagnostic when the pattern is NOT found in the file.

### Pattern with capture groups

Use `{0}`, `{1}`, etc. in the message to reference regex capture groups:

```yaml
custom_rules:
  - id: "project/no-hardcoded-urls"
    description: "Flag hardcoded URLs"
    severity: warning
    applies_to: ["src/**"]
    pattern: "https?://[^\\s\"']+"
    message: "Hardcoded URL found: {0}. Consider using a configuration variable."
```

### Custom rule fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique rule identifier (e.g., `"project/no-puts"`) |
| `pattern` | Yes | Regex pattern to match against each line |
| `description` | No | Human-readable description |
| `severity` | No | `error`, `warning` (default), `info`, or `hint` |
| `applies_to` | No | Array of file patterns (default: `["**/*.cr"]`) |
| `message` | No | Diagnostic message (supports `{0}`, `{1}` substitution) |
| `negate` | No | `true` to report when pattern is NOT found (default: `false`) |

Custom rules can be disabled or have their severity overridden using the `rules:` section, just like built-in rules:

```yaml
rules:
  project/no-puts:
    severity: error
  project/require-copyright:
    enabled: false
```

---

## How It Works

1. Claude Code reads `.lsp.json` and spawns the `amber-lsp` binary
2. They communicate via JSON-RPC over stdio (LSP protocol)
3. Every time a `.cr` file is saved, the LSP analyzes it against all enabled rules
4. Diagnostics (errors, warnings) are sent back to Claude Code
5. Claude sees the diagnostics and can self-correct

The LSP only activates for Amber projects — it checks for `shard.yml` with an `amber` dependency.

---

## Troubleshooting

**LSP not activating**: Verify `amber-lsp` is at the path specified in `.lsp.json`. Run it manually: `echo '' | /path/to/amber-lsp` — it should wait for input without errors.

**No diagnostics appearing**: Check that your project has a `shard.yml` with an `amber` dependency. The LSP skips non-Amber projects.

**Custom rule not working**: Verify the regex is valid. Test it: `crystal eval 'puts /your_pattern/.matches?("test line")'`. Remember to double-escape backslashes in YAML (`\\s` not `\s`).

**Binary not found**: Rebuild from the `amber_cli` repository: `crystal build src/amber_lsp.cr -o bin/amber-lsp --release`
