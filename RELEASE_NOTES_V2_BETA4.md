# Amber 2.0.0-beta.4

Amber 2.0.0-beta.4 gives the V2 web application a complete production static-
asset boundary. Applications keep editable CSS, JavaScript, images, fonts, and
other browser files under `app/assets/`; asset_pipeline compiles fingerprinted
release files and a manifest under `public/assets/`; Amber resolves that
manifest from views and serves its files with browser-correct headers.

This release is additive to beta.3. Existing beta.3 applications can update
their Amber version without rewriting controllers, models, migrations, or ECR
views. Applications adopt the new asset contract when they add a manifest and
switch view references to the manifest-aware helpers.

## What changed

- `Amber::Assets` loads and validates `public/assets/manifest.json`, reloads it
  during development, and caches it safely in production.
- `asset_path`, `image_tag`, `stylesheet_link_tag`, `favicon_tag`, and
  `javascript_importmap_tag` resolve logical paths through the manifest.
- Stylesheets, module scripts, and module preloads include SHA-256 Subresource
  Integrity metadata from the build manifest.
- The static pipe serves fingerprinted output with one-year immutable caching,
  non-fingerprinted output with revalidation, portable MIME types, configured
  response headers, `Vary: Accept-Encoding`, and optional `.gz` siblings.
- `AMBER_DATABASE_URL` remains the highest-priority database override, with
  `DATABASE_URL` supported as a hosting-friendly fallback.

## Supported fresh application

Amber CLI 2.0.5 generates this contract and builds the first manifest as part
of `amber new`:

```bash
brew install amberframework/amber_cli/amber_cli
amber new pet_tracker --type web
cd pet_tracker
shards install
amber assets check
amber generate scaffold Pet name:string:required species:string:required adopted:bool
amber database migrate
crystal spec
amber watch
```

Open <http://localhost:3000/> and <http://localhost:3000/pets>. The generated
HTML references fingerprinted CSS, JavaScript, SVG, and font URLs from
`public/assets/manifest.json`.

See the [beta installation guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.4/docs/beta-installation.md)
and [V1 to V2 migration guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.4/docs/migration-guide.md).

Please report framework/runtime issues at
<https://github.com/amberframework/amber/issues>, compiler issues at
<https://github.com/amberframework/asset_pipeline/issues>, and
CLI/template/install issues at
<https://github.com/amberframework/amber_cli/issues>.
