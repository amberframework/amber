# Amber V2 Beta Installation and Support

This is the release contract for Amber `2.0.0-beta.1` and Amber CLI `2.0.2`.
The goal is a repeatable first run, not a promise that every experimental
generator is production-ready.

## Supported beta path

| Surface | Beta status |
|---|---|
| macOS on Apple Silicon | Supported and release-gated |
| Linux on x86_64 | Supported and release-gated |
| Homebrew installation on those platforms | Supported |
| Direct release archive on those platforms | Supported |
| `amber new APP --type web` with ECR | Supported |
| Build, specs, server launch, homepage, and static assets | Release-gated |
| Intel macOS, Linux ARM64, and Windows | Not release-gated in this beta |
| Native application template | Preview |
| Persistence, auth, and resource generators | Preview |

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
brew tap amberframework/amber_cli
brew install amber_cli
amber --version
```

The expected CLI version is `2.0.2` or newer. If another executable is found,
run `command -v amber` and use the troubleshooting section below.

## Install a release archive

Choose the archive that matches the supported machine:

- Apple Silicon macOS: `amber_cli-darwin-arm64.tar.gz`
- x86_64 Linux: `amber_cli-linux-x86_64.tar.gz`

The following example installs CLI `v2.0.2`. On Linux, replace the two
`darwin-arm64` occurrences with `linux-x86_64`.

```bash
version=v2.0.2
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

## Verify the complete web-app path

Use a new directory name, then run every command below:

```bash
amber new amber_beta_smoke --type web
cd amber_beta_smoke
shards install
crystal spec
crystal build src/amber_beta_smoke.cr -o bin/amber_beta_smoke
amber watch
```

In another terminal:

```bash
curl --fail http://127.0.0.1:3000/
curl --fail http://127.0.0.1:3000/css/app.css
```

Both requests must succeed. The generated `shard.yml` must reference
`amberframework/amber` at `2.0.0-beta.1`; it should not point at a personal
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

Only the two platforms in the support table are release-gated. Building from
source can help contributors evaluate other platforms, but it is not an
installation guarantee for this beta.

### A preview generator needs another shard

The minimal web template intentionally has no ORM, database driver, attachment
library, or authentication shard. Do not add an unofficial or personal-fork
dependency merely to make a preview generator compile. Follow that component's
own release documentation or use the core web template until it is published.

## Report a beta problem

Open an issue in the repository that owns the failing step:

- Framework behavior: <https://github.com/amberframework/amber/issues>
- CLI, template, or binary: <https://github.com/amberframework/amber_cli/issues>
- Homebrew formula: <https://github.com/amberframework/homebrew-amber_cli/issues>

Include the OS and architecture, `crystal --version`, `amber --version`, the
install method, the exact command, and the complete error output.
