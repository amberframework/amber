# Amber V2 Beta Installation and Support

This is the release contract for Amber `2.0.0-beta.4` and Amber CLI `2.0.5`.
The goal is a repeatable first run, not a promise that every experimental
generator is production-ready.

## Supported beta path

| Surface | Beta status |
|---|---|
| macOS on Apple Silicon | Supported and release-gated |
| Linux on x86_64 | Supported and release-gated |
| Linux on ARM64 | Supported and release-gated |
| Windows on x86_64 | Generated web app, migrations, specs, and build are release-gated in CI |
| Homebrew on Apple Silicon macOS and x86_64 Linux | Supported |
| Release archives for Apple Silicon macOS, x86_64 Linux, and ARM64 Linux | Supported |
| `amber new APP --type web` with ECR | Supported |
| Grant models, SQLite, Micrate migrations, and resource scaffolds | Supported |
| Build, specs, server launch, homepage, static assets, and database CRUD | Release-gated |
| Intel macOS | Not release-gated in this beta |
| Native application template | Preview |
| Authentication generators | Preview |

## Prerequisites

Install Crystal 1.20 or newer, but earlier than 2.0, using the
[official Crystal instructions](https://crystal-lang.org/install/). Verify the
toolchain:

```bash
crystal --version
shards --version
git --version
```

## Install with Homebrew

The tap name contains an underscore:

```bash
brew install amberframework/amber_cli/amber_cli
amber --version
```

The fully qualified command follows Homebrew's tap-trust model and trusts only
the `amber_cli` formula. The installed executables are `amber` and `amber-lsp`.

The expected CLI version is `2.0.5` or newer. If another executable is found,
run `command -v amber` and use the troubleshooting section below.

## Install a release archive

Choose the archive that matches the supported machine:

- Apple Silicon macOS: `amber_cli-darwin-arm64.tar.gz`
- x86_64 Linux: `amber_cli-linux-x86_64.tar.gz`
- ARM64 Linux: `amber_cli-linux-arm64.tar.gz`

The following example installs CLI `v2.0.5`. On Linux, replace the two
`darwin-arm64` occurrences with `linux-x86_64` or `linux-arm64`.

```bash
version=v2.0.5
asset=amber_cli-darwin-arm64.tar.gz
curl -fLO "https://github.com/amberframework/amber_cli/releases/download/${version}/${asset}"
curl -fLO "https://github.com/amberframework/amber_cli/releases/download/${version}/${asset}.sha256"
shasum -a 256 -c "${asset}.sha256"
tar -xzf "${asset}"
install -m 0755 amber amber-lsp /usr/local/bin/
amber --version
```

Linux users may use `sha256sum -c` instead of `shasum -a 256 -c`. If
`/usr/local/bin` requires elevated privileges, prefix only the `install`
command with `sudo`.

## Build the CLI on Windows

Windows web applications are release-gated even though a standalone Windows
CLI archive is not published yet. Clone the CLI and install its exact
dependencies in PowerShell:

```bash
git clone https://github.com/amberframework/amber_cli.git
cd amber_cli
git checkout v2.0.5
shards install
```

Build the CLI and verify it before adding its directory to `PATH`:

```powershell
crystal build src/amber_cli.cr -o amber.exe --release
.\amber.exe --version
```

## Verify the complete web-app path

Use a new directory name, then run every command below:

```bash
amber new amber_beta_smoke --type web
cd amber_beta_smoke
shards install
amber assets check
amber generate scaffold Pet name:string:required species:string:required adopted:bool
amber database migrate
crystal spec
crystal build src/amber_beta_smoke.cr -o bin/amber_beta_smoke
amber watch
```

In another terminal:

```bash
curl --fail http://127.0.0.1:3000/
```

The request and `amber assets check` must succeed. Inspecting the page source
must show fingerprinted `/assets/...` URLs with `integrity="sha256-..."` on
the stylesheet and JavaScript module. The generated `shard.yml` must reference
`amberframework/amber` at `2.0.0-beta.4`; it should not point at a personal
fork or a moving branch.

## Update or remove

Homebrew:

```bash
brew update
brew upgrade amber_cli
# or
brew uninstall amber_cli
brew untap amberframework/amber_cli
```

For a direct installation, replace both installed binaries with the files from
the newer verified archive. Remove `/usr/local/bin/amber` and
`/usr/local/bin/amber-lsp` to uninstall.

## Troubleshooting

### The wrong `amber` runs

Amber V1 bundled a CLI, and old source builds may still be earlier in `PATH`:

```bash
type -a amber
amber --version
```

Remove or rename the stale executable, or place the new installation directory
earlier in `PATH`.

### Homebrew cannot install the binary on macOS

Run `brew update`, then reinstall:

```bash
brew reinstall amberframework/amber_cli/amber_cli
```

The beta CLI's macOS release binary must link against supported Homebrew
libraries and must not require `openssl@1.1`. Include the output of
`otool -L "$(command -v amber)"` when reporting a failure.

### The requested platform has no archive

Release archives are published for Apple Silicon macOS, x86_64 Linux, and ARM64
Linux. Windows is an application compile-and-run gate in CI but does not yet
have a standalone CLI archive; build the CLI from source there while the
packaging work is completed.

### An authentication or native preview needs another shard

The default web template includes Grant and SQLite, while `amber database`
provides Micrate migrations. Authentication, attachments, and native-app
features are separate preview surfaces. Follow each component's release
documentation instead of adding an unofficial dependency to make a preview
generator compile.

## Report a beta problem

Open an issue in the repository that owns the failing step:

- Framework behavior: <https://github.com/amberframework/amber/issues>
- CLI, template, or binary: <https://github.com/amberframework/amber_cli/issues>
- Homebrew formula: <https://github.com/amberframework/homebrew-amber_cli/issues>

Include the OS and architecture, `crystal --version`, `amber --version`, the
install method, the exact command, and the complete error output.
