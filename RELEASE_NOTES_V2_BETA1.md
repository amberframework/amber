# Amber 2.0.0-beta.1

Amber V2's first public beta establishes a tested, documented path for creating
an ECR web application with the standalone Amber CLI.

This is a prerelease. Expect breaking changes before Amber 2.0.0 and do not use
it for production workloads that cannot tolerate them.

## Install and create a web app

Install Amber CLI 2.0.2 or newer:

```bash
brew tap amberframework/amber_cli
brew install amber_cli
amber new my_app --type web
cd my_app
crystal spec
amber watch
```

See the [beta installation guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.1/docs/beta-installation.md)
for direct archives, checksums, update/uninstall steps, and troubleshooting.

## Release-gated surface

- Apple Silicon macOS and x86_64 Linux
- Homebrew and matching direct CLI archives
- ECR web application generation
- dependency installation, specs, application build, server start, homepage,
  and static CSS
- framework core, routing, typed configuration, Schema API, jobs, mailer,
  WebSockets, adapters, and testing helpers

## Major V2 changes

- CLI and LSP extracted to `amberframework/amber_cli`
- ECR is the only supported view engine; Kilt and Slang were removed
- runtime shard dependencies removed from framework core
- database drivers and ORM are explicit application choices
- typed, sectioned YAML with environment-variable overrides
- built-in jobs, mailer, Schema API, and adapter-backed infrastructure

Read the [V1 to V2 migration guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.1/docs/migration-guide.md)
before upgrading an existing application.

## Preview surfaces

Persistence/auth/API-resource generators, Grant integration, Gemma attachments,
the separate Asset Pipeline, and native app generation are not part of the
core beta release gate. Intel macOS, Linux ARM64, and Windows do not have
release-gated CLI archives in this beta.

Please report framework issues at
<https://github.com/amberframework/amber/issues> and CLI/template/install issues
at <https://github.com/amberframework/amber_cli/issues>.
