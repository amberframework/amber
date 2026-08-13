# Amber V2 schema, CBOR, COSE, and optimized routing: DigitalOcean round 27

Status: **VALIDATED for the measured workload.** This is the final rerun after integrating Amber V2's optimized routing and request-path work. It measures completed HTTP requests on an exact $4 DigitalOcean target; it is not a router-lookup microbenchmark or a production capacity promise.

## Result

| Full HTTP scenario | Median requests/s | Observed range | Median p50 | Median p99 |
|---|---:|---:|---:|---:|
| Generic JSON decode, no schema | 20,728 | 19,019-22,618 | 0.688 ms | 2.813 ms |
| Schema-validated JSON | 19,488 | 18,573-22,236 | 0.721 ms | 3.185 ms |
| Schema-validated CBOR | 21,742 | 19,904-23,256 | 0.646 ms | 2.921 ms |
| Authenticated COSE + schema + authenticated COSE | 14,443 | 10,962-15,160 | 1.006 ms | 3.612 ms |

For this eight-field request and five-field acknowledgement:

- Enforcing the request and response schema cost **6.0%** versus generic JSON decoding.
- Validated CBOR was **11.6% faster** than validated JSON and reduced the request body from 257 bytes to 223 bytes.
- Full bidirectional COSE was **25.9% slower** than validated JSON and **33.6% slower** than validated CBOR. That path authenticates and decrypts the request, validates it, then encodes, authenticates, and encrypts the response with a fresh nonce.
- All **7,974,608** measured requests returned HTTP 200. The 28 retained raw runs have a 100% success rate and no unexpected error categories.
- The service peaked at **16.6 MiB** on the 512-MB target.

The release-grade conclusion is that Amber can enforce the typed request and response contract at a median **19,488 completed JSON requests/second** in this constrained synthetic workload. CBOR more than recovers the measured schema cost. COSE makes its security cost visible while retaining a five-digit median.

## Before and after the integrated performance work

| Full HTTP scenario | Round 26 median | Round 27 median | Change |
|---|---:|---:|---:|
| Generic JSON decode, no schema | 13,889 | 20,728 | +49.2% |
| Schema-validated JSON | 12,987 | 19,488 | +50.1% |
| Schema-validated CBOR | 14,886 | 21,742 | +46.1% |
| Bidirectional COSE | 10,381 | 14,443 | +39.1% |

Round 26 used Amber `2.0.0-beta.4` as the schema branch base. Round 27 used commit `36bbceac51ee641082c1955c547caa941b93ff28`, which adds the optimized span router as the default and integrates the associated request, params, pipeline, and responder allocation work.

This is a controlled cloud before/after, not proof that the router alone caused every percentage point. The rounds used separate ephemeral droplets, so cloud-host variability cannot be eliminated. However, both rounds used the same exact DigitalOcean plans and region, the same reported target CPU model/family/cache, the same load-generator CPU model, the same 1,002-route workload, the same payloads, oha 1.14.0, 16 connections, rotating scenario order, and seven 15-second repetitions.

## What one request does

The benchmark installs 1,000 filler routes plus the two measured endpoints. Every request includes Crystal's HTTP/1.1 parsing and serialization, Amber route dispatch, controller construction, body handling, action execution, and response delivery.

The validated paths additionally perform:

1. media-type enforcement;
2. JSON, bounded CBOR, or COSE-plus-CBOR decoding;
3. coercion and constraints for request ID, UUID, email, integer range, boolean, enum, typed string array, and maximum note length;
4. typed access through the request-local schema;
5. response shape and HTTP status validation; and
6. negotiated JSON, CBOR, or COSE serialization.

The legacy `params.validation` API remains functional and deprecated for V2 upgrade compatibility. It is not used in this benchmark; these endpoints exercise the new automatically enforced schema contract.

## Environment and method

- Target: DigitalOcean `s-1vcpu-512mb-10gb`, 1 vCPU, 512 MB advertised RAM, 10 GB disk, $4/month at test time. Linux reported 469,236 KiB total RAM.
- Load generator: separate DigitalOcean `c-4`, four dedicated vCPUs and 8 GB RAM.
- Network: private isolated VPC in `nyc1`; the target bound only to its private address.
- Binary: release-mode Crystal 1.21.0 cross-compile for `x86_64-unknown-linux-gnu`, `x86-64-v2`, linked on Ubuntu 24.04.
- Tool: `oha` 1.14.0, 16 connections.
- Runs: 3-second warmup for every scenario, then seven rotating 15-second repetitions per scenario.
- Payloads: byte-identical within the round; JSON 257 bytes, CBOR 223 bytes, COSE Encrypt0 282 bytes.
- Cleanup: both short-lived droplets and the isolated VPC were destroyed before analysis; their absence was verified at `2026-08-13T15:38:27Z`.

The scenario order rotated by repetition. No slower run was classified away as an outlier.

## Boundaries on the claim

This is a synthetic in-memory acknowledgement endpoint. It deliberately excludes a database, external services, TLS termination, HTML rendering, application logging middleware, and public-internet latency. It establishes codec, validation, and framework request-path cost under constrained hardware. It does not establish how many concurrent users a particular application can support.

The `19,488 requests/second` result is therefore suitable as a precisely qualified framework benchmark, not as an unqualified promise that every Amber application will deliver that throughput. The earlier roughly 5,900-requests/second application result should remain a separate workload claim rather than being silently replaced by this synthetic endpoint result.

## Evidence

- Human-readable prior round: `benchmarks/DIGITALOCEAN_SCHEMA_CONTRACT_ROUND26.md`
- Machine-readable summary: `benchmarks/results/schema_contract_r27_cloud_summary.json`
- 28 raw `oha` runs: `benchmarks/results/schema_contract_r27_cloud_raw/`
- Target and load-generator evidence, JSON plus hexadecimal wire fixtures, hashes, OS and hardware reports: `benchmarks/results/schema_contract_r27_evidence/`
- Workload server: `benchmarks/schema_contract_http_server.cr`
- Rotating runner: `benchmarks/digitalocean/run_schema_contract_loadgen.sh`

The raw evidence is intentionally JSON because it is machine output. This report is the readable artifact for documentation and blog drafting.
