# CIDRAdmission Benchmarks

`CIDRAdmissionBenchmarkTarget` measures `IPAdmissionPolicy` construction and
the indexed Boolean `allows(_:)` path. The policy retains source rules for
`decision(for:)` diagnostics while compiling private, family-partitioned exact
coverage indexes for admission checks.

The benchmark package is intentionally separate from the public
`swift-cidr-admission` package so library users do not resolve benchmark-only
dependencies.

## Standard Commands

From the repository root:

```bash
./scripts/benchmarks.sh build
./scripts/benchmarks.sh list
./scripts/benchmarks.sh run
```

From the `Benchmarks/` package root:

```bash
swift build -c release --target CIDRAdmissionBenchmarkTarget
swift package benchmark list
swift package benchmark --target CIDRAdmissionBenchmarkTarget
```

## Benchmark Matrix

Lookup benchmarks cover IPv4 and IPv6 policies at these rule counts:

```text
0, 1, 10, 50, 100, 250, 500, 1,000, 10,000
```

The lookup scenario names retain their 0.1 source-fixture labels for historical
comparison. `first` and `last` now describe where the matching rule was placed
in the source configuration; they are not positions in a runtime linear scan:

- `policy.lookup.<family>.empty.defaultDeny`
- `policy.lookup.<family>.allowOnly.hit.first.<size>`
- `policy.lookup.<family>.allowOnly.hit.last.<size>`
- `policy.lookup.<family>.allowOnly.miss.<size>`
- `policy.lookup.<family>.denyOnly.hit.last.<size>`
- `policy.lookup.<family>.denyOnly.miss.<size>`
- `policy.lookup.<family>.combined.denyMissAllowLast.<size>`
- `policy.decision.<family>.combined.denyMissAllowLast.<size>`

Compile benchmarks measure configuration-to-policy construction:

- `policy.compile.<family>.allowOnly.<size>`
- `policy.compile.<family>.combined.<size>`

The 0.2.0 matrix also measures file-backed policy construction at 500, 1,000,
and 10,000 rules. Range and CIDR artifacts cover the same independently
generated network sets. `verifyIfPresent` uses no checksum file; `required`
reads and verifies an exact detached SHA-256 checksum before parsing, so their
difference shows the integrity-check overhead within the complete load path:

- `policy.load.<family>.<representation>.verifyIfPresent.<size>`
- `policy.load.<family>.<representation>.required.<size>`

## Results

The checked-in chart is the **0.1 linear-array baseline**, measured on an Apple
M1 Max running macOS 26.5.1 with Darwin
`25.5.0 Darwin Kernel Version 25.5.0: Mon Apr 27 20:38:56 PDT 2026; root:xnu-12377.121.6~2/RELEASE_ARM64_T6000 arm64`.

![IPAdmissionPolicy lookup p50 time by policy size](Results/lookup-time-p50.png)

Those numbers describe the released 0.1 implementation, not the 0.2 indexed
path. At 500 entries, that historical worst-case one-list scan was about
`795 ns` for IPv4 and `955 ns` for IPv6; the combined deny-miss plus allow-last
case was about `1.6 us` for IPv4 and `1.9 us` for IPv6. Do not infer current
performance from the baseline chart.

## 0.2.0 Snapshot

The following p99 measurements were recorded on 2026-08-08 on an Apple M1 Max
running macOS 26.6 and Swift 6.3.3. They are dated observations, not CI
thresholds. Indexed and detailed timings are per lookup; each combined case
misses a gapped deny index and matches the final source rule in a gapped allow
index.

| Family | Path | 500 rules | 1,000 rules | 10,000 rules |
| --- | ---: | ---: | ---: | ---: |
| IPv4 | indexed `allows(_:)` | 1.660 us | 1.854 us | 2.523 us |
| IPv4 | detailed `decision(for:)` | 1.871 us | 3.600 us | 35 us |
| IPv6 | indexed `allows(_:)` | 1.645 us | 1.832 us | 2.554 us |
| IPv6 | detailed `decision(for:)` | 2.316 us | 4.592 us | 45 us |

File construction includes reading one allow artifact, parsing every rule, and
building its exact-coverage index. These fixtures deliberately hold range and
CIDR cardinality equal so they isolate representation parsing cost. Real
`cidrmerge` output can contain fewer ranges than CIDRs, which may offset the
per-record difference.

| Family | Representation | Integrity | 500 rules | 1,000 rules | 10,000 rules |
| --- | --- | --- | ---: | ---: | ---: |
| IPv4 | CIDR | verify if present | 1.117 ms | 2.150 ms | 23 ms |
| IPv4 | CIDR | required | 1.144 ms | 2.238 ms | 21 ms |
| IPv4 | ranges | verify if present | 2.757 ms | 5.546 ms | 55 ms |
| IPv4 | ranges | required | 2.857 ms | 5.587 ms | 57 ms |
| IPv6 | CIDR | verify if present | 1.361 ms | 2.675 ms | 26 ms |
| IPv6 | CIDR | required | 1.373 ms | 2.679 ms | 26 ms |
| IPv6 | ranges | verify if present | 3.121 ms | 6.152 ms | 62 ms |
| IPv6 | ranges | required | 3.170 ms | 6.152 ms | 62 ms |

At this scale, required detached-checksum verification was small relative to
complete parse/index construction and sometimes within run-to-run noise. The
measurement command and compact results are also recorded in the private
cidrmerge runbook.

## Reading Results

`IPAdmissionPolicy` checks the deny coverage index before the allow coverage
index. The fast `allows(_:)` path uses those indexes; the detailed
`decision(for:)` path walks source rules only when a caller requests the first
matching `AdmissionRule` for diagnostics.

The existing filters remain useful for direct comparison with the 0.1 fixture
matrix:

```bash
./scripts/benchmarks.sh run --filter '^policy\.lookup\.v4\.combined\.denyMissAllowLast\.500$' --no-progress --time-units nanoseconds
./scripts/benchmarks.sh run --filter '^policy\.lookup\..*\.500$' --no-progress --time-units nanoseconds
```
