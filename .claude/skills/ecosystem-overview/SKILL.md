---
name: amber-ecosystem-overview
description: Amber V2 ecosystem map — how Amber framework, Grant ORM, Gemma, Amber CLI, Crystal Alpha, and Shards-Alpha fit together
user-invocable: false
---

# Amber V2 Ecosystem Overview

The Amber V2 ecosystem consists of 6 interconnected projects built on the Crystal programming language.

## Component Map

| Component | Repository | Purpose | Status |
|-----------|-----------|---------|--------|
| **Amber Framework** | `amberframework/amber` | Web framework: routing, controllers, WebSockets, middleware pipes, background jobs, mailer, Schema API, configuration, markdown renderer | v2.0.0-dev, 1,967 specs, zero runtime deps |
| **Grant ORM** | `crimson-knight/grant` | ActiveRecord-pattern ORM replacing Granite. Model definitions, associations (has_many, belongs_to, has_one), queries, migrations, validations | ~80-85% Rails 8+ parity |
| **Gemma** | (external shard) | File attachment toolkit with Grant integration. Provides `has_one_attached` and `has_many_attached` for models. Similar to Shrine/ActiveStorage | Active development |
| **Amber CLI** | `amberframework/amber_cli` | Code generators, scaffolding, project templates, LSP support. Separate executable from the framework | Separate project |
| **Crystal Alpha** | Local: `/Users/crimsonknight/open_source_coding_projects/crystal/` | Fork of Crystal compiler. Incremental compilation (7 phases), WASM (wasm32-wasi), cross-platform (iOS/Android) | Crystal 1.19.1, targeting 1.20 |
| **Shards-Alpha** | Local: `/Users/crimsonknight/open_source_coding_projects/shards/` (branch: `alpha`) | Modified package manager. Drop-in shards replacement with AI agent config distribution from dependencies, MCP server, compliance tools | Alpha branch |

## Dependency Graph

```
                    Crystal Alpha (compiler)
                          |
                    Shards-Alpha (package manager)
                          |
            +-------------+-------------+
            |             |             |
      Amber Framework   Grant ORM    Gemma
            |             |           / |
            +------+------+----------+  |
                   |                    |
              Amber CLI          Grant + Gemma
                   |              (integrated)
                   v
            Your Amber App
```

- **Crystal Alpha** compiles all Crystal code. Provides incremental compilation, WASM targets, and iOS/Android cross-compilation.
- **Shards-Alpha** resolves dependencies and distributes AI agent configurations from shard `ai_docs` declarations.
- **Amber Framework** provides the web layer. Zero runtime dependencies -- fully self-contained.
- **Grant ORM** handles database persistence. Separate shard, replacing Granite for V2.
- **Gemma** adds file attachment support. Integrates with Grant models.
- **Amber CLI** generates project scaffolding. Separate executable.

## Version Compatibility

| Component | Crystal Version | Notes |
|-----------|----------------|-------|
| Amber Framework | >= 1.0.0, < 2.0 | Crystal stdlib ECR for templates |
| Grant ORM | >= 1.0.0 | ActiveRecord pattern |
| Gemma | >= 1.0.0 | Depends on Grant |
| Crystal Alpha | 1.19.1 (targeting 1.20) | Superset of standard Crystal |
| Shards-Alpha | Compatible with Crystal Alpha | Drop-in replacement for shards |

## Agent Directory

The Amber ecosystem provides specialized AI agents for different tasks:

| Agent | File | Purpose | Use When |
|-------|------|---------|----------|
| **amber-ecosystem-expert** | `.claude/agents/amber-ecosystem-expert.md` | Ecosystem navigation, project setup, tool selection, delegation | Starting a new project, choosing between tools, understanding how projects fit together |
| **amber-framework-engineer** | `.claude/agents/amber-framework-engineer.md` | Framework internals, architecture, code review | Modifying the Amber framework source, adding subsystems, reviewing framework code |
| **amber-app-developer** | `.claude/agents/amber-app-developer.md` | Application development, public API usage, best practices | Building apps WITH Amber: routes, controllers, models, views, jobs, mailer |

## Skills Reference

| Skill | Path | Covers |
|-------|------|--------|
| **crystal-language** | `.claude/skills/crystal-language/` | Crystal types, macros, concurrency, blocks -- language foundations for Amber |
| **amber-ecosystem-overview** | `.claude/skills/ecosystem-overview/` | This document -- ecosystem map and component relationships |
| **amber-routing** | `.claude/skills/routing/` | Route DSL, resourceful routes, named routes, constraints, API versioning |
| **amber-controllers** | `.claude/skills/controllers/` | Controller lifecycle, filters, rendering, redirects, params |
| **amber-pipelines** | `.claude/skills/pipelines/` | Middleware composition, built-in pipes, custom pipes |
| **amber-websockets** | `.claude/skills/websockets/` | Channels, client sockets, presence, message decoders |
| **amber-schema-api** | `.claude/skills/schema-api/` | Request schemas, validators, parsers |
| **amber-jobs** | `.claude/skills/jobs/` | Background jobs, work-stealing, queue adapters |
| **amber-mailer** | `.claude/skills/mailer/` | Email composition, SMTP/memory adapters |
| **amber-testing** | `.claude/skills/testing/` | ContextBuilder, assertions, WebSocket test helpers |
| **amber-sessions-security** | `.claude/skills/sessions-security/` | Session stores, encryption, key rotation |
| **amber-configuration** | `.claude/skills/configuration/` | Typed config, env overrides, custom registry |
| **amber-views-components** | `.claude/skills/views-components/` | ECR templates, layouts, partials, helpers |

## Quick Links

- **Amber Framework source**: `src/amber/` (entry point: `src/amber.cr`)
- **Amber specs**: `spec/amber/` (1,967 specs)
- **Test runner**: `./bin/amber_spec` (runs specs, formatting, and linting)
- **Crystal Alpha**: `/Users/crimsonknight/open_source_coding_projects/crystal/`
- **Shards-Alpha**: `/Users/crimsonknight/open_source_coding_projects/shards/` (branch: `alpha`)
- **Crystal Book docs**: `/Users/crimsonknight/open_source_coding_projects/crystal-book/docs/`
