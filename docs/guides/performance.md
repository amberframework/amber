# Performance: the fastest, smallest app from the start

This guide lists the patterns, tools and processes that give an Amber V2 app
its best speed and its smallest memory and link footprint from the first
build. Each recommendation names the measurement or the code it rests on.
Most of them are already the default in an app from `amber new`; the guide
says what each default does, so you keep it when you change things.

## Where things stand

| Piece | Where it comes from |
|---|---|
| Mica runs `Regex` and `YAML` | crystal-alpha 1.21.0-incremental-6 and later (incremental-8 is current) |
| Contiguous release units | crystal-alpha 1.21.0-incremental-7 and later |
| 8 KB collector blocks for your programs | the `agent-crystal` Homebrew formula on arm64 macOS |
| 8 MiB starting heap, page cache, stateless views | apps from Amber CLI 2.0.12 and later |
| `-Dwithout_openssl` (cookies on Beryl) | Amber 2.0.0-beta.14, Grant 0.26.0 and asset_pipeline 0.39.0 (apps from Amber CLI 2.0.15) |
| `-Dwithout_zlib` (gzip on Mica) | Amber 2.0.0-beta.14, Grant 0.26.0 and asset_pipeline 0.39.0 (apps from Amber CLI 2.0.15) |

Unless a section says otherwise, numbers were measured on an Apple M1 Max
running macOS 26 with an app from `amber new -d sqlite` plus a scaffolded
`Post`, built with `crystal-alpha build --release`, in production mode.
The machine was shared with other jobs, so requests per second moved from
run to run. Peak memory, CPU time per request and bytes allocated per
request are the steadier figures.

## The checklist

| Step | What to do | What it gives you |
|---|---|---|
| 1 | Build with crystal-alpha and write regexes Mica runs | No PCRE2 or libyaml linked; every search linear in its input |
| 2 | Check every regex against Mica in CI | A pattern Mica cannot run fails CI, not a deploy |
| 3 | Make the hottest patterns static | Compile 24× as fast as PCRE2-JIT, no allocation per search |
| 4 | Build with `-Dwithout_zlib` and `-Dwithout_openssl` when TLS ends at a proxy | No libz, libssl or libcrypto in the binary |
| 5 | Keep the 8 MiB starting heap | Every measured route under 17 MiB peak |
| 6 | Build with the formula's collector (8 KB blocks on arm64 macOS) | About 3.7 MiB less peak memory than 16 KB blocks |
| 7 | Keep the default release units | The single-object build's code layout, built in parallel |
| 8 | Serve shared pages from the page cache; warm stateless views at boot | A cached page costs 16.0 µs of CPU per request |
| 9 | Measure each change with `scripts/probe_app.rb` | Linkage, behavior, peak RSS and peak footprint in one run |

## 1. crystal-alpha and Mica-compatible regexes

**Run from: the application root.**

```bash
crystal-alpha build --release src/my_app.cr -o bin/my_app
```

From crystal-alpha 1.21.0-incremental-6, Crystal's own `Regex` and `YAML`
run on Mica's engines, written in Crystal, so the binary links neither
PCRE2 nor libyaml. Regex literals, `=~`, `$~`, `String#match`, `gsub`,
`scan` and `split` keep their API. Every search runs in time linear in its
input, under a work budget and a deadline.

What it cost and saved, measured:

- On a production Amber V2 app (the Scribe license server), CPU, memory and
  latency per request were equal to PCRE2 within the 95% intervals on every
  route. Its 370 specs passed on both engines. The release binary was 1.21×
  as large (5,018,672 against 4,163,632 bytes).
- On the generated app, peak RSS was 20.48 to 20.66 MiB on the Mica
  defaults and 20.69 to 20.75 MiB with `-Duse_pcre2 -Duse_libyaml`; the
  binary was 4,149,968 against 3,987,888 bytes (crystal-alpha
  1.21.0-incremental-7 release notes).
- On Mica's benchmark (round 11, Mica v0.2.0), Amber's 26 patterns
  searching 64 KiB in a freshly started program take 0.734 of PCRE2-JIT's
  time: 70.38 µs against 95.86 µs, 1.36× as fast. Over all 479 cases, every
  group is at or under PCRE2-JIT's time on warm search, compile, first
  search and first search in a new process.
- YAML parsing is 1.5 to 1.9× as fast as libyaml on a 19-file corpus of
  Kubernetes, GitHub Actions, shard and Amber configuration files.

### What Mica leaves out, and the rewrite

Mica runs the patterns whose searches stay linear. A regex literal that uses
one of the constructs below stops the build with a message that names the
fix; a pattern built at run time raises `Regex::UnsupportedSyntaxError`.

| Construct | Rewrite |
|---|---|
| Lookahead `(?=` `(?!`, lookbehind `(?<=` `(?<!` | Match the wider text and check the context in Crystal, or capture the context as a group |
| Backreferences `\1`, `\k<name>` | Capture both parts and compare them in Crystal |
| Atomic groups `(?>...)`, possessive quantifiers `a++` | Drop them; Mica never backtracks |
| `\K` | Capture the part after `\K` as a group |
| Recursion, conditionals, backtracking verbs | A parser, alternation, or two patterns |

Each rewrite below compiles and runs on stock Crystal and on crystal-alpha.

**File: the class or module under `src/` that owns the value.**

```crystal
module NumberFormatting
  DIGIT_GROUP = /\d{1,3}/

  # Before: digits.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  def self.with_delimiters(digits : String) : String
    digits.reverse.scan(DIGIT_GROUP).map(&.[0]).join(",").reverse
  end
end

module Accounts
  ORDINARY_USERNAME = /\A\w+\z/

  # Before: /^(?!admin)\w+$/
  def self.ordinary_username?(name : String) : Bool
    ORDINARY_USERNAME.matches?(name) && !name.starts_with?("admin")
  end
end

module Prices
  DOLLAR_AMOUNT = /\$(\d+)/

  # Before: /(?<=\$)\d+/
  def self.dollar_amount(text : String) : String?
    if amount = DOLLAR_AMOUNT.match(text)
      amount[1]
    end
  end
end

module Prose
  WHITESPACE_RUN = /\s+/

  # Before: /\b(\w+) \1\b/
  def self.has_a_doubled_word?(text : String) : Bool
    text.split(WHITESPACE_RUN).each_cons(2).any? { |pair| pair[0] == pair[1] }
  end
end
```

Keep request data out of pattern source. A pattern built from the same text
is compiled once and reused; a pattern interpolated from each request
(`/#{params["name"]}:/`) is compiled on every request. Compare request
values in Crystal (`==`, `starts_with?`, `includes?`).

If one pattern truly needs PCRE2, build with `-Duse_pcre2`; the app then
links PCRE2 again. `-Duse_libyaml` does the same for YAML.

## 2. The regex-on-mica check

The compiler checks a literal only when the program reaches it, so a
pattern in a method no spec calls compiles until the day a request calls
it. Mica's `scripts/check_regex_literals.cr` reads every file instead.
Amber runs it in CI as the `regex-on-mica` job through
`scripts/check_regex_on_mica.sh`, which fetches Mica at a pinned commit and
verifies its Git tree before it runs. Amber CLI runs the same check over
every file its generators write.

**Run from: the application root**, after copying Amber's
`scripts/check_regex_on_mica.sh` into your app's `scripts/`.

```bash
scripts/check_regex_on_mica.sh src spec
```

It uses stock `crystal` by default (set `CRYSTAL` to choose another
compiler that honors `CRYSTAL_PATH`). A clean run and a failing run:

```text
0 patterns Mica cannot run in 1 file (5 checked)
```

```text
bad/bad.cr:2:13: "(\\d{3})(?=\\d)" lookahead (at 7) is not supported
1 pattern Mica cannot run in 1 file (1 checked)
```

It exits 1 when it finds a pattern, so it gates CI as it is. A pattern kept
on purpose for PCRE2 alone is passed over when its line, or the line above,
holds the comment `# mica: pcre2 only`. Amber's own run covers 328 patterns
in 498 files.

## 3. Static regexes for the hottest patterns

A pattern on every request (a route constraint, a token format) can be
compiled while the app builds. Its tables become read-only data in the
binary, and its searches allocate nothing.

**File: `shard.yml`, under `dependencies:`** (Mica v0.2.0, pinned by commit).

```yaml
  mica:
    github: amberframework/mica
    commit: a3a3fd60c1a4b5141727de7a640a2c0b8cc367d7
```

**File: the class that validates the value, under `src/`.**

```crystal
require "mica"

module Downloads
  BUILD_ID = Mica::Regex.static(/\A[0-9]+\z/)

  def self.build_id?(candidate : String) : Bool
    BUILD_ID.matches?(candidate)
  end
end
```

Against PCRE2-JIT over 412 cases (round 11): compile 24× as fast
(159.3 ns against 3.86 µs), first search 11× as fast (5.44 µs against
61.31 µs), first search in a new process 6.2× as fast (43.68 µs against
269.96 µs), warm search 1.97× as fast (20.66 µs against 40.64 µs).

The argument must be a literal known at build time. A pattern whose tables
would be too large stays on the runtime engine, and the build says so:

```text
Mica::Regex.static: "\\b\\w+\\b" stays on the runtime engine: its tables take 1425408 bytes, over the static limit of 524288
```

Narrow such a pattern (a literal prefix, a `\A` anchor, `[A-Za-z0-9_]` in
place of `\w` when the input is ASCII), or keep it as an ordinary literal.

## 4. `-Dwithout_zlib` and `-Dwithout_openssl`

**Run from: the application root.**

```bash
crystal-alpha build --release -Dwithout_zlib -Dwithout_openssl src/my_app.cr -o bin/my_app
```

Crystal's `HTTP::Server` requires `openssl` and the `compress` libraries
unless these flags are given, so every web program links libssl, libcrypto
and libz by default. With the flags, Amber does that work in Crystal:

| Flag | What Amber uses instead | What the flag turns off |
|---|---|---|
| `-Dwithout_zlib` | `Amber::Pipe::Compression` gzips and deflates with a pinned copy of Mica's DEFLATE encoder (`src/amber/vendor`). Grant's compressed encrypted columns and asset_pipeline's precompressed assets and cached pages use Mica too | `HTTP::Client` asks for no compression and raises on a compressed answer; the server never inflates a request body (Amber answers those `415` in any build) |
| `-Dwithout_openssl` | `MessageVerifier`, `MessageEncryptor` and COSE run on a pinned copy of Beryl (`Amber::Beryl`): cookies are sealed with XChaCha20-Poly1305 under a key from HKDF-SHA256 | The HTTPS listener and SMTP STARTTLS raise `Amber::Exceptions::TLSNotCompiledIn`, which names the flag; `HTTP::Client` cannot call `https://` URLs |

So `-Dwithout_openssl` fits an app whose TLS ends at a proxy or load
balancer and which calls no HTTPS service itself. `-Dwithout_zlib` fits
every Amber app on the versions in the table at the top. Your own
`require "compress/gzip"` or `OpenSSL` call links the library again.

Measured on a generated shop app (Amber `v2-dev` at `8cd0512c`):

| Build | `otool -L` lines naming libz | zlib symbols |
|---|---:|---:|
| plain `--release` | 1 | 10 |
| `--release -Dwithout_zlib` | 0 | 0 |

The `-Dwithout_zlib` build served `GET /` gzipped from the page cache,
gzipped the `/products/new` form through `Amber::Pipe::Compression`,
answered a gzip request body `415`, and made an `HTTP::Client` call.
Mica's output is within 1% of `HTTP::CompressHandler`'s size on every spec
case. Each response's encoder keeps its tables (about 270 KB) in `malloc`
memory outside the collected heap and frees them when the response closes.

`scripts/check_linkage.sh` gates both flags in Amber's CI: the flagged
build must link no libz (no `inflate`, `deflate` or `crc32` symbol) and no
libssl or libcrypto (no `EVP_`, `SSL_` or `OPENSSL_` symbol), and still
answer `GET`; the unflagged control must show them, so the check can fail.

Cookies written by an earlier Amber (format version 1, AES-256-CBC with
HMAC) are still read and are rewritten in version 2 on their next save.
Version 2 cookies cannot be read by an earlier Amber, so a rollback signs
visitors out once.

## 5. The 8 MiB starting heap

**File: `config/environments/production.yml`, under `server:`.**

```yaml
server:
  gc_initial_heap_mib: 8
```

The collector fills its starting heap before it collects, so this one
number trades memory against CPU. Apps from Amber CLI 2.0.12 start at
8 MiB in every environment. `Amber::Server.start` grows the heap to this
size before the first request (`GrowHeapToStartingSize`); 0 keeps the
collector's own size, and a heap already larger (for example from
`GC_INITIAL_HEAP_SIZE`) is left alone.

Measured at 32 connections (amberframework/amber_cli#60):

| Route | Peak RSS, 8 / 16 MiB | CPU per request, 8 / 16 MiB |
|---|---:|---:|
| GET / (page cache) | 15.22 / 23.45 MiB | 16.0 / 15.4 µs |
| GET /api/posts (JSON, 50 rows) | 15.45 / 24.00 MiB | 98.1 / 82.5 µs |
| POST /posts (form, CSRF) | 16.81 / 25.59 MiB | 101.3 / 85.8 µs |
| GET /posts/new (form, gzip) | 15.03 / 23.67 MiB | 64.8 / 63.0 µs |

- **Memory first (a small server):** keep 8 MiB.
- **CPU first, on allocation-heavy JSON or form routes:** 16 MiB used 16 to
  18% less CPU per request there, for 8.2 to 8.8 MiB more peak memory.
  Raise it for that environment only.
- **Below 8 MiB:** 4 MiB and 0 cost CPU at low connection counts (JSON at
  one connection: 188 and 204 µs per request against 178 µs at 8 MiB) and
  saved no steady memory at 32 connections.

For one process, `AMBER_SERVER_GC_INITIAL_HEAP_MIB=16` overrides the file.

## 6. Collector block sizes

The collector hands out memory in heap blocks, and a block goes back to the
operating system only when every object in it is dead and it covers whole
memory pages. arm64 macOS has 16 KB pages. The `agent-crystal` Homebrew
formula therefore builds the collector twice there: 8 KB blocks for the
programs crystal-alpha builds (in `libexec/gc`, first on its library path),
and 16 KB blocks linked into the compiler. Linux arm64 gets the build
machine's page size up to 16 KB; x86_64 keeps 4 KB.

Measured on the generated app, three interleaved rounds each
(crimson-knight/homebrew-agent-crystal#15):

| Collector | Peak RSS | Peak footprint |
|---|---:|---:|
| Homebrew bdw-gc, 4 KB blocks | 21.86 to 22.02 MiB | 16.36 to 16.53 MiB |
| 8 KB blocks (the formula today) | 21.41 to 21.48 MiB | 15.92 to 16.00 MiB |
| 16 KB blocks | 25.16 to 25.30 MiB | 19.81 to 19.88 MiB |

To see which collector a binary carries, build and run this program with
the same compiler and flags as the app. It should print `8192` on arm64
macOS with the formula's collector, and `otool -L` should list no `libgc`.

**File: a scratch file outside the app, for example `gc_block_size.cr`.**

```crystal
list_of_block_sizes = {65_536, 32_768, 16_384, 8_192, 4_096}
block_size = list_of_block_sizes.find do |candidate|
  LibGC.size(GC.malloc((candidate // 2 - 24).to_u64)) == candidate // 2
end
puts "heap block size: #{block_size}"
```

## 7. Release units

`--release` builds one optimized module and, by default, writes it as at
most 8 object files in parallel (`--release-units NUM`, at most
`--threads`). From crystal-alpha 1.21.0-incremental-7, each unit is a
contiguous run of functions, so the linked binary keeps the single-object
build's function order and code that runs together stays on the same pages
(crimson-knight/crystal#24). Earlier compilers dealt functions out round
robin.

| Release units | Peak RSS (three rounds) | Peak footprint |
|---|---:|---:|
| 8, round robin (before) | 20.19 / 20.22 / 20.23 MiB | 14.72 / 14.67 / 14.70 MiB |
| 8, contiguous (now) | 19.91 / 19.89 / 19.81 MiB | 14.73 / 14.70 / 14.64 MiB |
| 1 | 19.83 / 19.88 / 19.80 MiB | 14.70 / 14.72 / 14.69 MiB |

Keep the default: it matches a single-unit build in memory and keeps the
parallel build. Peak footprint does not move, because the pages it changes
are clean pages of the executable (see section 9).

## 8. View caching

An app from Amber CLI 2.0.12 or later caches views in three layers. Keep
each one when you add pages.

**Whole pages.** A scaffold's `index` and `show` actions answer through
`Components::Cache.page_cache`; its write actions clear exactly the pages
they changed. The first request stores the page, the second stores a gzip
copy and an ETag, and later requests are answered from those bytes, with
`304` when the browser already has them.

**File: the controller under `src/controllers/`.**

```crystal
class HomeController < ApplicationController
  def index
    Components::Cache.page_cache.answer(context, "home") do
      render("index.ecr")
    end
  end
end
```

The memory limit is set in `config/initializers/page_cache.cr` (32 MiB
unless `PAGE_CACHE_MB` says otherwise). In the measurements of section 5,
the cached `GET /` cost 16.0 µs of CPU per request, against 64.8 µs for the
fully rendered, gzipped `GET /posts/new` form.

Use it only for pages that are the same for every visitor. Public read
pages run on the generated `lean_read` pipeline, with no session, flash or
CSRF pipe; a page with per-visitor content moves to `routes :web` and
renders with a plain `render`. The cache lives inside one process, so keep
`server.process_count` at 1, its default, or a write in one process leaves
the others serving the old page.

**Stateless views.** Layout pieces with no runtime state, such as the
generated `SiteHeader` and `SiteFooter` in `src/components/`, are
`Components::StatelessView` structs. `src/<app>.cr` renders them once with
`Components::StatelessView.warm_all` before `Amber::Server.start`, and the
boot log reports how many were warmed and how many bytes they hold.

**Asset tags.** `stylesheet_link_tag`, `javascript_include_tag`,
`image_tag`, `favicon_tag` and `javascript_importmap_tag` render each tag
once per asset manifest and return the stored HTML afterward
(amberframework/amber#1458). A tag with extra attributes, or a public URL
(`/...`, `https:`, `data:`), is rendered every time, so pass logical paths
on the tags every page carries. On a fully rendered page this took bytes
allocated per request from 22,752 to 16,112 and CPU per request from
24.6 µs to 17.7 µs.

## 9. Measuring: `scripts/probe_app.rb`

`scripts/probe_app.rb` builds the evidence for one binary in one run. It
reads linkage (`otool -L` and `nm` for PCRE2 and GMP), checks behavior
(`GET /`, gzip with `Vary: Accept-Encoding`, a CSRF form `POST /posts`, a
gzip request body and a `charset=UTF-7` form both answered `415`), drives
15 s of `GET /` and 15 s of `GET /posts/new` at 32 connections with `oha`,
and reads the server's peak RSS and peak footprint from `/usr/bin/time -l`.

It runs on macOS and needs `oha`. The app is `amber new -d sqlite` plus a
scaffolded `Post` with `title` and `body` fields, migrated and built with
`--release`.

**Run from: anywhere; pass the app directory and the binary.**

```bash
/usr/bin/ruby path/to/amber/scripts/probe_app.rb ~/apps/probe ~/apps/probe/bin/probe 3187 8 > probe-8-run1.json
```

The last argument is the starting heap in MiB. Run each variant at least
twice, interleaved (A, B, B, A), on a machine with nothing else running.
The Amber 2.0.0-beta.13 release check, same compiler, two runs each:

| Field | beta.13 app | beta.12 app |
|---|---:|---:|
| `bytes` | 4,239,392 | 4,283,104 |
| `otool_pcre2_lines`, `nm_pcre2_symbols` | 0, 0 | |
| `peak_rss_mib` | 22.44 / 24.70 | 24.94 / 24.97 |
| `peak_footprint_mib` | 19.38 / 19.31 | |
| `get_root_requests_per_second` | 49,851 / 24,217 | 34,299 / 33,568 |

Requests per second halved between two runs of the same binary on a busy
machine, while footprint moved by 0.07 MiB. Compare variants on memory,
CPU per request and bytes per request, and treat requests per second as a
rough check.

### Peak RSS against peak footprint

`/usr/bin/time -l` prints both, and they answer different questions.

- **Peak RSS** (`maximum resident set size`) counts every page the process
  had in memory, including clean pages read from the executable and shared
  libraries. The system can drop those and read them again. RSS moves with
  code layout and with how much of the binary a request path touches.
- **Peak footprint** (`peak memory footprint`) counts the memory charged to
  the process: dirty and compressed pages, which is mostly the collector's
  heap, stacks and `malloc` memory. It is the figure macOS uses to decide
  which process to stop when memory runs short.

Read footprint for heap questions (starting heap, block size, allocation
per request) and RSS for code-layout questions (release units, binary
size). The release-units change in section 7 moved peak RSS by about
0.3 MiB and footprint not at all. The block sizes in section 6 moved both,
because they change the heap. In the beta.13 runs above, RSS differed by
2.26 MiB between two runs of one binary while footprint differed by
0.07 MiB, so a footprint change is the one to trust first.

## Sources

- Mica as the default engine, the real-app comparison and its binary size:
  crystal-alpha 1.21.0-incremental-6 release notes (crimson-knight/crystal#19).
- Engine cost on the generated app: crystal-alpha 1.21.0-incremental-7
  release notes.
- Regex speed: Mica round 11 (Mica `f0bb0f6`, in v0.2.0), official harness,
  479 runtime and 412 static cases. YAML speed: Mica's YAML benchmark of
  November 22, 2026 (amberframework/mica#20).
- The regex check: `scripts/check_regex_on_mica.sh`, amberframework/amber#1466
  and #1468, amberframework/amber_cli#65.
- `-Dwithout_openssl`: amberframework/amber#1465. `-Dwithout_zlib`:
  amberframework/amber#1467, crimson-knight/grant#80,
  amberframework/asset_pipeline#28, and the generated-app proof of
  November 22, 2026.
- Starting heap: amberframework/amber_cli#60. Page cache and stateless
  views: amberframework/amber_cli#53. Asset tags: amberframework/amber#1458.
- Collector blocks: crimson-knight/homebrew-agent-crystal#15. Release
  units: crimson-knight/crystal#24.
- `scripts/probe_app.rb` results: the Amber 2.0.0-beta.13 release check.
