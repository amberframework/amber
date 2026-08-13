# Getting Started

This guide creates the supported Amber V2 beta application: a server-rendered
web app using ECR templates and the standalone Amber CLI.

## Prerequisites

- A platform and installation method listed in the beta support guide
- Crystal 1.20 or newer (but earlier than Crystal 2.0)
- Git and `shards`
- Amber CLI 2.0.6 or newer

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

- Amber `2.0.0-beta.5` from `amberframework/amber`
- ECR templates
- typed, sectioned environment configuration
- a manifest-backed static-asset pipeline for CSS, JavaScript, images, fonts,
  and other browser files
- Grant models with SQLite as the zero-configuration development database
- Micrate-powered migrations through `amber database`

Choose `--database pg` or `--database mysql` when creating the app if you need
a server database. The generator writes the matching driver, connection, and
environment configuration into the new project.

## Verify before you edit

Run the generated specs and build the application:

```bash
crystal spec
amber assets check
crystal build src/my_app.cr -o bin/my_app
```

Start the development watcher:

```bash
amber watch
```

Open <http://localhost:3000>. View the page source and follow its fingerprinted
`/assets/stylesheets/app-....css` URL to confirm that the manifest, helper, and
static server agree. The stylesheet and JavaScript module tags include
`integrity="sha256-..."`. Stop the watcher with `Ctrl-C`.

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

## Add a database-backed resource

Generate the model, migration, controller, schema, views, route, and specs:

```bash
amber generate scaffold Pet name:string:required species:string:required adopted:bool
amber database migrate
crystal spec
```

The model is written to `src/models/pet.cr`, its SQL migration to
`db/migrations/`, and its form partial to `src/views/pet/_form.ecr`. Start the
app and open <http://localhost:3000/pets>.

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
    version: 2.0.0-beta.5

crystal: ">= 1.20.0, < 2.0"
```

Then run `shards install` and configure the server as described in the
[routing](guides/routing.md) and [configuration](guides/configuration.md)
guides.

## Generator support during the beta

The web application template, Grant models, SQLite migrations, and resource
scaffolds are release-gated together. Authentication, API-only resource, and
native-app generators remain preview surfaces. See the CLI's generator support
table before relying on a preview surface in a project.

## Next steps

- [Beta installation and troubleshooting](beta-installation.md)
- [Routing](guides/routing.md)
- [Configuration](guides/configuration.md)
- [Schema API](guides/schema-api.md)
- [Background jobs](guides/background-jobs.md)
- [Mailer](guides/mailer.md)
- [Testing](guides/testing.md)
- [Migration from Amber V1](migration-guide.md)
