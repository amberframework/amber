# Amber V2 schema, CBOR, and COSE: DigitalOcean round 26

Status: **VALIDATED for the measured workload.** These results measure a full HTTP endpoint on an exact $4 DigitalOcean target. They are not router-lookup numbers and they are not a production application capacity promise.

## Result

| Full HTTP scenario | Median requests/s | Observed range | Median p50 | Median p99 |
|---|---:|---:|---:|---:|
| Generic JSON decode, no schema | 13,889 | 12,620-16,083 | 0.968 ms | 4.174 ms |
| Schema-validated JSON | 12,987 | 12,462-14,757 | 1.009 ms | 4.435 ms |
| Schema-validated CBOR | 14,886 | 13,745-15,649 | 0.887 ms | 3.944 ms |
| Authenticated COSE + schema + authenticated COSE | 10,381 | 7,812-10,729 | 1.347 ms | 4.743 ms |

For this eight-field request and five-field acknowledgement:

- Enforcing the request and response schema cost **6.5%** versus generic JSON decoding.
- Validated CBOR was **14.6% faster** than validated JSON and reduced the request body from 257 bytes to 223 bytes.
- Full bidirectional COSE was **20.1% slower** than validated JSON and **30.3% slower** than validated CBOR. That scenario authenticates and decrypts the request, validates it, then encodes, authenticates, and encrypts the response with a fresh nonce.
- All **5,492,972** measured requests returned HTTP 200. The 28 retained raw runs have a 100% success rate and no unexpected transport errors.

The honest release conclusion is that real schema validation is affordable on the smallest server in this workload, CBOR more than recovered that cost, and bidirectional authenticated encryption has a visible but still five-digit-requests-per-second ceiling. A public post should show all four rows; publishing only the fastest binary format would hide the assurance being purchased.

## What one request does

The benchmark installs 1,000 filler routes plus the two measured endpoints. Every measured request includes Crystal's HTTP/1.1 parsing and serialization, Amber route dispatch, controller construction, body handling, action execution, and response delivery.

The validated paths additionally perform:

1. media-type enforcement;
2. JSON, bounded CBOR, or COSE-plus-CBOR decoding;
3. coercion and constraints for request ID, UUID, email, integer range, boolean, enum, typed string array, and maximum note length;
4. typed access through the request-local schema;
5. response shape and HTTP status validation; and
6. negotiated JSON, CBOR, or COSE serialization.

This is the before/after that the router-only and decoder-only experiments could not provide. It includes the actual validation contract and both halves of the response lifecycle.

## Environment and method

- Target: DigitalOcean `s-1vcpu-512mb-10gb`, 1 vCPU, 512 MB advertised RAM, 10 GB disk, $4/month at test time. Linux reported 469,232 KiB total RAM.
- Load generator: separate DigitalOcean `c-4`, four dedicated vCPUs and 8 GB RAM.
- Network: private isolated VPC in `nyc1`; the target bound only to its private address.
- Binary: release-mode Crystal 1.21.0 cross-compile for `x86_64-unknown-linux-gnu`, `x86-64-v2`, linked on Ubuntu 24.04.
- Tool: `oha` 1.14.0, 16 connections.
- Runs: 3-second warmup for every scenario, then seven rotating 15-second repetitions per scenario.
- Payloads: byte-identical files across repetitions; JSON 257 bytes, CBOR 223 bytes, COSE Encrypt0 282 bytes.
- Target service peak: 13.7 MiB measured by systemd; current memory at evidence collection was 10.2 MiB.
- Cleanup: both short-lived droplets and the isolated VPC were destroyed at `2026-08-13T15:06:17Z` and their absence was verified.

The scenario order rotated by repetition. Absolute throughput drifted enough to make a single favorable run misleading, so the table uses the median and keeps the full observed range. No slower run was classified away as an outlier.

## Boundaries on the claim

This is a synthetic in-memory acknowledgement endpoint. It deliberately excludes a database, external services, TLS termination, HTML rendering, application logging middleware, and public-internet latency. It establishes codec and validation cost under constrained hardware; it does not establish how many concurrent users a particular application can support.

The schema branch was based on Amber `2.0.0-beta.4` commit `a2128cdb4fef07025e0cc1c1578d4c807ae6c274`. The separately measured optimized-router line still needs to be integrated into the release candidate before publishing an absolute final-release throughput headline. That does not invalidate the relative schema/codec comparison here: all four scenarios used the same binary, route table, machine, and runner.

## Evidence

- Machine-readable summary: `benchmarks/results/schema_contract_r26_cloud_summary.json`
- 28 raw `oha` runs: `benchmarks/results/schema_contract_r26_cloud_raw/`
- Target and load-generator evidence, JSON plus hexadecimal wire fixtures, hashes, OS and hardware reports: `benchmarks/results/schema_contract_r26_evidence/`
- Workload server: `benchmarks/schema_contract_http_server.cr`
- Rotating runner: `benchmarks/digitalocean/run_schema_contract_loadgen.sh`

The raw evidence is intentionally JSON because it is machine output. This report is the human-readable interpretation and should be the artifact linked from documentation or a blog draft.
