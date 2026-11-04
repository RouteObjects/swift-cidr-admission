# Detailed Decisions: Project The Peer Once

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Captured on 2026-10-30, separately from all earlier snapshots. This experiment
tests a production candidate for `IPAdmissionPolicy.decision(for:)`, including
address and range rules, not just the network-only diagnostic from the
[previous investigation](../2026-10-30-patched-cidr-detailed-decision-benchmark-1.38.1/README.md).

**Both variants already use the pending three-annotation `swift-cidr` patch.**
The baseline here is the roughly 100 us decision, not the earlier unpatched
roughly 3 ms decision. The repository manifests and lockfiles were not changed;
these timings do not describe the currently published `swift-cidr` 0.8.0 alone.

## Findings

Preparing the peer once substantially improves long network scans, improves
mixed-rule scans, and preserves the tested admission semantics. It is not a
uniform performance improvement: empty policies and immediate address/range
matches become about 2-3 ns slower on this Mac. The candidate is left
uncommitted for review with that tradeoff visible.

Each table entry below is the arithmetic mean of two independently captured
run medians, not a pooled-sample median. At 10,000 rules **in each list**, a
decision misses all deny rules and matches the final allow rule, evaluating
up to 20,000 rules:

| Family | Metrics | Baseline p50 (us) | Project-once p50 (us) | Speedup |
| --- | --- | ---: | ---: | ---: |
| IPv4 | Full | 97.823 | 30.639 | 3.19x |
| IPv4 | Timing only | 98.015 | 30.511 | 3.21x |
| IPv6 | Full | 103.679 | 42.431 | 2.44x |
| IPv6 | Timing only | 103.263 | 40.895 | 2.53x |

Mean full-metrics throughput medians increase from 10,235 to 32,671 decisions/s
for IPv4 and from 9,655 to 23,583 decisions/s for IPv6. Throughput is exported
independently rather than derived from averaged wall-time medians.
Full/timing differences are small relative to the long-scan improvement, but
they are not identical; no statistical significance or universal speedup is claimed.

Mixed lists alternate address, network, and range rules and have 1,000 rules
per list. Full-metrics results, in us:

| Family | Scenario | Baseline | Project once |
| --- | --- | ---: | ---: |
| IPv4 | Deny miss, allow last | 7.107 | 4.833 |
| IPv4 | Both miss, default allow | 7.043 | 4.813 |
| IPv6 | Deny miss, allow last | 7.147 | 5.147 |
| IPv6 | Both miss, default allow | 7.085 | 5.125 |

## Short-Path Tradeoff

These full-metrics values are in **ns per operation** and are medians of
1,000-operation batch means, averaged across two runs. They are not
individual-call latency percentiles:

| Scenario | IPv4 baseline / candidate | IPv6 baseline / candidate |
| --- | ---: | ---: |
| Empty, default deny | 3.167 / 5.709 | 3.105 / 5.627 |
| Empty, default allow | 3.167 / 5.647 | 3.209 / 5.689 |
| First address rule denies | 5.251 / 7.503 | 5.211 / 7.961 |
| First range rule denies | 5.627 / 8.211 | 5.649 / 8.167 |
| First network rule denies | 7.461 / 6.791 | 7.835 / 7.273 |
| First network rule allows | 7.689 / 6.583 | 8.065 / 7.231 |

The candidate prepares the peer before knowing which rule kind will match,
including when no rule exists. The extra short-path cost is consistent with
that upfront work and the changed generated decision body. This experiment
does not isolate the cost of a single helper instruction or test lazy projection.
The private immutable peer avoids shared caching or mutable evaluator state.

All full-metrics allocation and ARC counter medians were zero. That does not
prove that every sample allocated nothing or establish a memory-leak guarantee.

## Implementation And Semantics

Production changes are confined to `Sources/CIDRAdmission/IPAdmissionPolicy.swift`.
A private `DecisionPeer` constructs a host-address view once and
reuses it for the deny and allow scans. Network rules use ordinary typed
`contains(address:)` calls on that view. Address and range rules delegate to
the unchanged public `AdmissionRule.contains` implementation.

The policy's source arrays, their order, the Boolean coverage indexes, public
API, equality/hash inputs, and public standalone rule containment are unchanged.
Deny remains first, each list retains first-match selection, the original
source rule is returned in the reason, and the configured default is used on
a miss. Candidate prefix context is ignored for membership without changing
stored prefix context on source address rules. IPv4-mapped IPv6 stays IPv6.

The new tests compare complete decisions with the pre-change public-rule scan
and also check agreement with indexed `allows`:

- 31,740 decisions over every legal IPv4/IPv6 peer prefix length for selected boundary peers and policy combinations.
- 8,192 seeded decisions over mixed, reordered, duplicate rules with both default actions.
- Overlapping address/network/range permutations, opposite-family rules, and deny precedence.
- Explicit stored-prefix checks on equal address rules, because ordinary rule equality intentionally ignores that context.
- Zero/all-ones addresses, host and allow-all networks, inclusive range boundaries, misses, and IPv4-mapped IPv6 addresses.

The macOS [baseline](evidence/baseline-decision-excerpt.txt) and
[candidate](evidence/patched-decision-excerpt.txt) assembly show host preparation
before the scans and inline network matching in the candidate. Non-network
branches still call public rule containment. On native x86-64 Linux, both
supported toolchains optimized the captured candidate decision function to
contain no call instructions; excerpts and checks are in `linux/`.
There are no additional `@inlinable` or forced-inline annotations in this
admission candidate. Detailed decisions remain linear scans; this is a
constant-factor improvement, not an indexed reason lookup.

## Capture Method

- Admission base: `5d01867915f257d9d2086a510efe1c20f697b69a`, with the existing reference-sampling harness plus identical new controls/tests in both copies.
- CIDR base: `cdc2e592beb9095875bc42fc4c269396b20d99e3` (`0.8.0`), with the same local annotations on `IPPrefix.contains(address:)`, `CIDR.mask`, and `FixedWidthInteger.networkMask(for:)` in both copies.
- Only the admission policy implementation differs between the two measured source inventories.
- Apple M1 Max, 10 logical CPUs, 64 GiB; macOS 26.7.1, build 25G241; Apple Swift 6.3.3, Xcode 26.6.
- Benchmark 1.38.1, malloc-interposer 1.6.1, Crypto 5.0.3; other dependency pins held fixed.

Ordinary SwiftPM Release builds used isolated source copies, not Git worktrees.
Temporary SwiftPM dependency edits selected the patched CIDR source; only its
pin is removed from the temporary effective lockfile. All other pins and all
real repository lockfiles are unchanged. Source, effective graph, workspace
state, and executable hashes were checked around the captures.

The run order is baseline full/timing, candidate full/timing/timing/full,
then baseline timing/full. Each capture contains the original 16 detailed
network cases at 1, 10, 50, 100, 250, 500, 1,000, and 10,000 rules per family,
plus 16 new controls. In artifact names and CSV fields, `patched` means the
admission project-once candidate; CIDR is patched in **both** variants.

Full metrics record throughput, wall time, three malloc counters, object
allocations, retains, releases, and retain/release delta. Timing-only requests
wall time and throughput from the same executable with allocation/ARC metric
hooks unrequested. It is not a separately linked interposer-free build.
Allocation stacks are disabled. Unrelated compiler activity was allowed to
finish before capture; other background activity was not controlled or
continuously monitored. Per-run load and power state are retained.

Existing cases use the `reference` profile. New short controls use batches of
1,000; mixed-list controls are single-operation samples. The new controls
consume the complete decision, while existing cases consume `isAllowed` from
the decision. Compare a case across variants, not unlike fixtures as if they
measured exactly the same workload. Default discovery remains 174 cases.
The new controls require `CIDR_ADMISSION_BENCHMARK_PEER_PROJECTION=1` and can
be selected with `--filter '^projection\.'`.

## Validation And Artifacts

All 61 tests in eight suites passed in Debug and Release on macOS Swift 6.3.3
and native x86-64 `linux-validation-host` with Swift 6.2.4 and 6.3.3: six passing test
configurations. Linux validation includes source/pin checks and generated
code, not a Linux performance comparison. Mac timing penalties and speedups
must not be assumed to apply unchanged to Linux or iOS.

Eight captures produced 256 case observations and 1,408 metric records with
no cases below 30 samples. Minimum sample count is 1,812 overall and 2,715
across candidate captures. Per-run p50/p99, throughput, sample units, and
counter medians are in `runs/*/summary.csv`; native baseline distributions,
raw exports, commands, and logs are retained alongside them.

See [comparison.csv](comparison.csv), [validation.json](validation.json),
[preservation.json](preservation.json), and [Sampling And Percentiles](../../../Sampling.md).
`evidence/` and `linux/` contain source hashes, patches, dependencies,
build/test logs, and disassembly. `capture-scripts/` preserves session-specific
orchestration for audit, not general-purpose repository commands.
Verify this bundle with `shasum -a 256 -c SHA256SUMS` from this directory.

Earlier snapshots, historical charts/tables, and existing unrelated changes
are untouched. No files were staged or committed. Discarding this experiment
requires removing only its new files/index link and reversing its scoped
policy/benchmark-registration patch, not resetting the worktree.
