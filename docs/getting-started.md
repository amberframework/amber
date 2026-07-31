# Getting Started

This guide creates the supported Amber V2 beta application: a server-rendered
web app using ECR templates and the standalone Amber CLI.

## Prerequisites

- macOS on Apple Silicon or Linux on x86_64
- Crystal 1.20 or newer (but earlier than Crystal 2.0)
- Git and `shards`
- Amber CLI 2.0.2 or newer

Follow the [beta installation guide](beta-installation.md) if `amber --version`
does not work yet.

## Create the application

```bash
amber new my_app --type web
cd my_app
shards install
```

`--type web` is explicit so the command remains reproducible as more app types
are added. The generated application uses:

- Amber `2.0.0-beta.2` from `amberframework/amber`
- ECR templates
- typed, sectioned environment configuration
- a static-file pipeline for the generated CSS and JavaScript
- no database or ORM dependency by default

Database selection records generator metadata; it does not add an ORM or a
database driver to this minimal web template.

## Verify before you edit

Run the generated specs and build the application:

```bash
crystal spec
crystal build src/my_app.cr -o bin/my_app
```

Start the development watcher:

```bash
amber watch
```

Open <http://localhost:3000>. Also load
<http://localhost:3000/css/app.css> to confirm the static-file pipeline is
working. Stop the watcher with `Ctrl-C`.

## Add a route

The generated app includes `HomeController`. Add this action to
`src/controllers/home_controller.cr`:

```crystal
def health
  respond_with 200 do
    json({status: "ok", amber: Amber::VERSION})
  end
end
```

Then add the route inside the generated `routes :web` block:

```crystal
get "/health", HomeController, :health
```

Restart `amber watch` if needed and visit <http://localhost:3000/health>.

## Configuration

Generated environment files use V2's typed structure:

```yaml
name: "my_app"

server:
  host: "127.0.0.1"
  port: 3000
  secret_key_base: "replace_this_in_production"

logging:
  severity: "debug"
  colorize: true
```

Environment variables override YAML values:

```bash
AMBER_SERVER_HOST=0.0.0.0 AMBER_SERVER_PORT=8080 amber watch
```

See the [configuration guide](guides/configuration.md) for every section and
override.

## Manual framework installation

The CLI is the supported onboarding path. If you need to add Amber to an
existing Crystal application, pin the beta rather than the moving development
branch:

```yaml
dependencies:
  amber:
    github: amberframework/amber
    version: 2.0.0-beta.2

crystal: ">= 1.20.0, < 2.0"
```

Then run `shards install` and configure the server as described in the
[routing](guides/routing.md) and [configuration](guides/configuration.md)
guides.

## Generator support during the beta

The web application template itself is the release-gated path. Generators that
depend only on Amber core can be evaluated inside it. Persistence,
authentication, API-resource, and native-app generators are preview surfaces
until their external dependencies and platform matrices are released and
documented. See the CLI's generator support table before relying on one in a
project.

## Next steps

- [Beta installation and troubleshooting](beta-installation.md)
- [Routing](guides/routing.md)
- [Configuration](guides/configuration.md)
- [Schema API](guides/schema-api.md)
- [Background jobs](guides/background-jobs.md)
- [Mailer](guides/mailer.md)
- [Testing](guides/testing.md)
- [Migration from Amber V1](migration-guide.md)
