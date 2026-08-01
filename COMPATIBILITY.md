# Crystal ↔ Amber compatibility

Which Crystal compiler versions can build which Amber releases. "Verified" means we
compiled the framework, ran the full spec suite, and (for the most recent rows)
generated a new app with `amber new`, compiled it, and served requests with it.

## Supported combinations

| Amber release | Crystal requirement (declared) | Verified working | Known broken | Status |
|---|---|---|---|---|
| **2.0.0-beta.2** (v2 beta) | `>= 1.20.0, < 2.0` | 1.20.3, 1.21.0 | < 1.20.0 | **Active development** (`v2-dev`) |
| **2.0.0-beta.1** | `>= 1.20.0, < 2.0` | 1.20.x | < 1.20.0 | Superseded by beta.2 |
| **1.5.0** | `>= 1.20.0, < 2.0` | 1.20.3, 1.21.0 | — | **Current v1 release** |
| 1.4.1 / 1.4.0 | `>= 1.0.0, < 2.0` (declared) | 1.9.2 (CI), 1.20.3 | **1.21.0+** — does not compile | Upgrade to 1.5.0 |
| 1.3.x | `>= 1.0.0, < 2.0` (declared) | ~1.6 era (CI of the day) | 1.21.0+ | EOL — upgrade |
| 1.2.x | `>= 1.0.0, < 2.0` (declared) | ~1.2 era (CI of the day) | 1.21.0+ | EOL — upgrade |
| 0.36.0 and earlier | `0.35.x` and earlier | pre-1.0 compilers only | all Crystal 1.x | EOL |

## Why 1.4.1 and earlier break on Crystal 1.21

Crystal 1.21 enables multithreading by default, and `Process.fork` fails at
**compile time** (`Error: Process fork is unsupported with multithreaded mode`).
Amber ≤ 1.4.1 used `Process.fork` in `Amber::Cluster.fork`, which is reachable
from `Amber::Server#run`, so every app failed to compile — even apps that never
enable cluster mode. Amber 1.5.0 replaces the fork with a `Process.new` spawn of
the app binary (the same mechanism v2 uses), preserving `process_count` /
master-worker semantics.

Two secondary breakages also fixed in 1.5.0:

- **ameba ≤ 1.6.4 does not compile on Crystal 1.21**, and both the framework and
  the generated app template pinned `~> 1.5.0`, so `shards install` failed in
  development. Both now pin `1.7.0-dev` (the first ameba tag with Crystal 1.21
  support); the pin moves to `~> 1.7.0` once ameba tags a stable release.
- Old declared constraints (`>= 1.0.0`) overstate reality; 1.5.0 declares
  `>= 1.20.0` to match what is actually tested.

## Policy

- **v1** (`master`): tested in CI against the two most recent Crystal minor
  releases (currently 1.20.x and 1.21.x). Older Crystal versions may work but
  are not supported.
- **v2** (`v2-dev`, 2.0.0 betas): requires Crystal 1.20+. Tested against
  `latest` on Linux and macOS.
- A new Crystal minor release that breaks Amber is treated as a bug in Amber:
  file an issue with the compiler error and the Crystal version.

_Last verified 2026-08-01 on macOS arm64 (local) — spec suites: v1 master 487/0,
v2 beta.2 2320/0, both on Crystal 1.20.3 and 1.21.0._
