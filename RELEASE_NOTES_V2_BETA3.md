# Amber 2.0.0-beta.3

Amber 2.0.0-beta.3 is the framework release for the database-backed web
application that Amber CLI 2.0.4 generates by default. The supported path now
includes Grant models, SQLite, Micrate migrations, and complete HTML resource
scaffolds instead of stopping at a database-free homepage.

## What changed

- Schema controllers parse browser form bodies, including bodies already read
  by routing or CSRF protection.
- Background-job workers can steal queued work without corrupting request
  activity accounting.
- ECR view paths are normalized on Windows.
- The HTML/JSON `respond_with` behavior is documented with executable examples.

## Install and exercise persistence

Install Amber CLI 2.0.4, then generate and migrate a real resource:

```bash
brew install amberframework/amber_cli/amber_cli
amber new pet_tracker --type web
cd pet_tracker
shards install
amber generate scaffold Pet name:string:required species:string:required adopted:bool
amber database migrate
crystal spec
amber watch
```

Open <http://localhost:3000/pets>. The generated model lives at
`src/models/pet.cr`, its SQL migration is under `db/migrations/`, and its ECR
form partial is `src/views/pet/_form.ecr`.

Apple Silicon macOS and x86_64 Linux have CLI release archives. Linux ARM64 and
Windows x86_64 generated web applications are compile-gated in CI; their CLI
binaries are built from source for this beta.

See the [beta installation guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.3/docs/beta-installation.md)
and [V1 to V2 migration guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.3/docs/migration-guide.md).

Please report framework issues at
<https://github.com/amberframework/amber/issues> and CLI/template/install issues
at <https://github.com/amberframework/amber_cli/issues>.
