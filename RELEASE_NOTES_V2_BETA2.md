# Amber 2.0.0-beta.2

Amber 2.0.0-beta.2 supersedes beta.1 for new Amber CLI web applications.
It keeps the same public beta surface and fixes application startup on Crystal
1.21's default multithreaded runtime.

## Compatibility fix

- Replaced the server cluster launcher's `Process.fork` reference with portable
  process spawning.
- Release-gated on Apple Silicon macOS and x86_64 Linux with Crystal 1.21.
- Fresh ECR web apps are tested through dependency installation, specs, core
  generators, build, server launch, homepage delivery, and static CSS.

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

The generated application pins `amberframework/amber` at `2.0.0-beta.2` and
uses ECR. Database drivers, persistence, auth, Grant, Gemma, Asset Pipeline,
and native application generation remain opt-in preview surfaces rather than
part of the core beta release gate.

See the [beta installation guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.2/docs/beta-installation.md)
and [V1 to V2 migration guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.2/docs/migration-guide.md).

Please report framework issues at
<https://github.com/amberframework/amber/issues> and CLI/template/install issues
at <https://github.com/amberframework/amber_cli/issues>.
