# Cross-Framework Router Benchmark: Fairness Notes

## What We Are Comparing

These benchmarks compare **routing engines only** -- the component that takes
a URL path and matches it against a set of registered route patterns. We are
NOT comparing full web frameworks, which include middleware pipelines,
controller dispatch, request/response handling, template rendering, and many
other subsystems that affect real-world performance.

## Routers Tested

| Router | Used By | Strategy |
|--------|---------|----------|
| Amber V2 engine | Amber V2 | Segment tree with hash-indexed fixed segments |
| amber_router v0.4.4 | Amber V1 | Segment tree with linear scan |
| radix v0.4.1 | Kemal | Radix tree (compressed trie) |

## Why Lucky and Athena Are Not Included

Lucky and Athena use **compile-time routing** via Crystal macros and
annotations. Their routes are resolved during compilation, meaning there is no
runtime router object to benchmark. This is a fundamentally different
architectural trade-off: they exchange longer compile times for zero runtime
dispatch cost. This strategy is not directly comparable in micro-benchmarks
that measure runtime iterations per second.

## Why Spider-Gazelle Is Not Included

Spider-Gazelle does not have a standalone routing shard. Their
`action-controller` framework (v7.6.1) internally uses `lucky_router` from
the Lucky framework. Since Lucky's router relies on compile-time macro
resolution, there is no standalone runtime routing engine to benchmark.

## Path Matching Only

Some routers (like `radix`) are purely path-based and do not support HTTP
method dispatch (GET, POST, etc.). To ensure a fair comparison, all benchmarks
test **path matching only** -- finding the route that matches a given URL path
regardless of HTTP method.

## Same Machine, Same Crystal Version

All benchmarks were run on the same machine in the same session using Crystal
1.18.2. Amber V1 and V2 data was collected in prior benchmark runs on the
same hardware; radix benchmarks were run fresh. The `--release` flag was used
for all compiled benchmark binaries.

## Route Patterns

All routers were loaded with identical route patterns at each tier:
- **Fixed segments**: `/resource_N/action_M` (60% of routes)
- **Variable segments**: `/resource_N/:id/action_M` (35% of routes)
- **Glob segments**: `/resource_N/files/*filepath` (5% of routes)

Using 30 resources and 10 actions, this scheme supports up to 10,000 unique
routes per tier without collisions.

## Glob Support Varies

All three routers support glob (catch-all / wildcard) patterns, though with
slightly different internal strategies. The `radix` shard handles globs inline
during its trie traversal. The Amber routers use dedicated glob segment types
within their segment trees.

## Not-Found Behavior

Not-found lookup performance varies significantly between implementations due
to architectural differences in early-exit strategies. The `radix` shard can
reject unknown paths very quickly at the trie root level when the first
characters do not match any stored prefix, resulting in much higher not-found
IPS values. This is an inherent advantage of the compressed trie data
structure for rejection, not necessarily an indicator of overall routing
quality.

## Benchmark Methodology

- **Warmup**: 2 seconds per measurement
- **Calculation**: 5 seconds per measurement
- **Tool**: Crystal's `Benchmark.ips` (reports iterations per second)
- **Memory**: Crystal's `Benchmark.memory` (reports bytes allocated per call)
- **Tiers tested**: 50, 100, 500, 1,000, 5,000, 10,000 registered routes
- **Compilation**: `--release` flag (LLVM optimizations enabled)
