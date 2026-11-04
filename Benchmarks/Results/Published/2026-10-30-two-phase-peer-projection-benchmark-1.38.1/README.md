# Detailed Decisions: Two-Phase Peer Projection

> Sanitized historical copy; see [publication notes](../README.md). Embedded hashes and validation claims refer to the original capture.

Captured October 30, 2026 local time (October 31 UTC), separately from all
earlier snapshots. This follows the
[lazy-cache comparison](../2026-10-30-lazy-peer-projection-benchmark-1.38.1/README.md).
All four evaluators use the same pending three-annotation `swift-cidr` patch.
These are not timings for unmodified published `swift-cidr` 0.8.0.

## Conclusion

The two-phase implementation removes per-rule projection-state checks and
preserves the tested admission semantics. It recovers most of the lazy cache's
IPv4 long-scan regression and improves mixed scans, but is **not an across-the-board
improvement**. IPv6 long scans are essentially unchanged from the lazy cache;
eager projection remains faster on long scans. Immediate network matches and
very small network policies become slower because of the phase handoff and
changed generated code.

The candidate is left uncommitted for review. Artifact names mean:

- `baseline`: original per-rule projection evaluator.
- `eager`: project once at function entry.
- `deferred`: previous lazy cache with a per-rule state check.
- `phased`: new two-phase scan with an immutable host peer in phase two.

## Long Scans

Values are arithmetic means of two separately captured run medians, not pooled
medians. These are single-operation samples in **microseconds**. A decision
misses 10,000 deny rules and matches the last of 10,000 allow rules, evaluating
up to 20,000 rules.

| Family | Metrics | Original | Eager | Lazy cache | Two-phase |
| --- | --- | ---: | ---: | ---: | ---: |
| IPv4 | Full | 97.439 | 30.255 | 39.855 | 32.175 |
| IPv4 | Timing only | 96.543 | 29.927 | 39.487 | 32.175 |
| IPv6 | Full | 103.199 | 40.319 | 45.599 | 45.215 |
| IPv6 | Timing only | 105.343 | 40.351 | 45.711 | 44.959 |

Two-phase is about 19% faster than the lazy cache for IPv4, but only 0.8-1.6%
faster for IPv6; the latter is too small here to claim a meaningful improvement.
It remains 6-8% slower than eager projection for IPv4 and 11-12% slower for IPv6.
Against the original evaluator, it is about 3.0x faster for IPv4 and 2.3x for IPv6.
Mean full-metrics throughput medians are 31,103 and 22,143 decisions/s,
respectively. Throughput is exported independently rather than inferred from
the reciprocal of averaged wall times.

Mixed lists alternate address, network, and range rules, with 1,000 rules in
each list. Full-metrics times in microseconds:

| Family | Scenario | Original | Eager | Lazy cache | Two-phase |
| --- | --- | ---: | ---: | ---: | ---: |
| IPv4 | Deny miss, allow last | 7.189 | 4.771 | 5.667 | 5.085 |
| IPv4 | Both miss, default allow | 7.043 | 4.751 | 5.647 | 5.063 |
| IPv6 | Deny miss, allow last | 7.127 | 5.127 | 5.961 | 5.397 |
| IPv6 | Both miss, default allow | 7.273 | 5.087 | 5.875 | 5.315 |

## Short-Path Tradeoffs

Full-metrics values below are **nanoseconds per operation**, averaging two run
medians of 1,000-operation batch means. They are not individual-call latency
percentiles. Each cell shows **original / eager / lazy cache / two-phase**.

| Scenario | IPv4 | IPv6 |
| --- | ---: | ---: |
| Empty, default deny | 3.188 / 5.543 / 3.625 / 3.626 | 3.167 / 5.583 / 3.563 / 3.646 |
| Empty, default allow | 3.188 / 5.543 / 3.646 / 3.605 | 3.188 / 5.521 / 3.605 / 3.751 |
| First address rule denies | 5.209 / 7.605 / 6.127 / 5.503 | 5.231 / 7.773 / 6.063 / 5.501 |
| First range rule denies | 5.711 / 8.215 / 6.397 / 6.147 | 5.625 / 8.105 / 6.419 / 6.063 |
| First network rule denies | 7.627 / 6.669 / 6.835 / 9.611 | 7.649 / 7.271 / 6.835 / 9.691 |
| First network rule allows | 7.563 / 6.649 / 7.251 / 10.423 | 8.109 / 7.189 / 7.251 / 10.587 |

Two-phase keeps empty, address-first, and range-first cases within roughly
0.3-0.6 ns of the original evaluator. However, first-network matches cost
roughly 2-3 ns more than the original and 2-4 ns more than eager projection.
The one-deny-miss plus one-allow-match case also regresses: 13.671 ns for IPv4
and 14.211 ns for IPv6, versus eager's 8.295 ns and 9.399 ns, and the original's
12.711 ns and 13.107 ns. Removing a per-rule cache branch does not remove the
fixed cost of entering phase two.

## Implementation And Code Generation

Phase one scans deny rules, then allow rules, using the original peer. Address
and range matches can return without projection. Opposite-family networks do
not trigger projection. At the first same-family network:

1. Construct one private immutable host-address view.
2. Resume phase two at the triggering rule, not the following rule.
3. Finish the current list; if this was deny and nothing matched, scan allow
   with the same projected peer.
4. Return the first matching source rule, or the configured default.

Phase two uses ordinary typed `contains(address:)` for networks and the
unchanged public containment implementation for address/range rules. It has
no cache flag, lazy getter, or projection inside its loop. It uses array
indices to resume without copying a suffix or introducing `ArraySlice`.
No inline annotations, unsafe buffers, public API additions, policy-level
cache state, or indexed reason lookup were introduced. Detailed decisions
remain linear scans; indexed `allows(_:)` is unchanged.

The macOS [generated-code excerpts](evidence/phased-decision-excerpt.txt) show that
`DecisionPeer.firstMatch` remains an out-of-line function. Its network
containment is inlined, and its only call site is public rule containment on
the non-network branch. There are no host-construction or cache-getter calls
inside that scan. Ordinary bounds, rule-kind, and family checks remain.
The separate function handoff is consistent with the observed first-network
penalty, but this experiment does not isolate the cost of one instruction or
prove that the call alone explains the difference.

## Semantics And Tests

Deny precedence, first source match, defaults, source arrays/order, original
rules in decision reasons, equality/hash inputs, and standalone rule containment
are unchanged. Peer prefix context is ignored for membership without rewriting
source address-rule context. IPv4 and IPv6 stay separate, including mapped
IPv6 addresses. The host view is local to one decision; no shared mutable
state is added.

All **64 tests in eight suites passed in Debug and Release** on macOS Swift
6.3.3 and native x86-64 Linux with Swift 6.2.4 and 6.3.3: six passing test
configurations. Existing differential tests cover 31,740 decisions across all legal
prefix lengths for selected boundary peers/policies, 8,192 seeded mixed-policy
decisions, source-order permutations, duplicate address-rule contexts, delayed
projection, and concurrent calls sharing one immutable policy. They compare
complete decisions against the unchanged public-rule scan, separately check
returned source-prefix context, and verify agreement with indexed `allows`.

The new phase-position test adds **360 differential decisions**. It moves the
first same-family network through the list, checks that the triggering rule
is not skipped, checks later address/range/network matches and misses, covers
both defaults and families, and exercises projection in either deny or allow.

The [initial SSH attempt](evidence/linux-validation.json) failed during agent
signing, before upload. After the user made 1Password available, the retry
completed all four native Linux configurations on `linux-validation-host` (Ubuntu 24.04.5
LTS, x86-64 LXC). The [native verification](linux/verification.json) confirms
the source archive, source hashes, and unchanged remaining dependency pins.
Each toolchain was selected through a per-command `PATH`, without changing
the server's default toolchain or existing checkouts.

Native [Swift 6.2.4](linux/6.2.4-decision-excerpt.txt) and
[Swift 6.3.3](linux/6.3.3-decision-excerpt.txt) assembly contain no call
instructions inside `firstMatch`; calls from `decision(for:)` enter that
function at phase boundaries. These are semantic and generated-code checks,
not a Linux performance comparison. All timing tables above are from macOS.

## Capture Method

- Admission base: `5d01867915f257d9d2086a510efe1c20f697b69a`.
- CIDR base: `cdc2e592beb9095875bc42fc4c269396b20d99e3`, with identical pending `@inlinable` changes to `IPPrefix.contains(address:)`, `CIDR.mask`, and `FixedWidthInteger.networkMask(for:)`.
- Apple M1 Max, 10 logical CPUs, 64 GiB; macOS 26.7.1 (25G241); Apple Swift 6.3.3; Xcode 26.6.
- Benchmark 1.38.1, malloc-interposer 1.6.1, Crypto 5.0.3; remaining dependency pins held fixed.

Four variants, two metric profiles, and two runs per profile produce **16
captures, 512 case observations, and 2,816 metric records**. Each capture has
the same 32 cases: 16 network decisions at 1, 10, 50, 100, 250, 500, 1,000, and
10,000 rules per list, and 16 short/mixed controls. Minimum sample count is
1,593, with no case below 30 samples. All full-metrics allocation/ARC counter
medians are zero; this is not proof that every sample allocated nothing or a
memory-leak guarantee.

All measurements are new. The three control release binaries were reused
after checking source inventories, pins, executable/interposer hashes, and
toolchain/environment identity. Two-phase was built in a new isolated source
copy, not a Git worktree. Benchmark compilation inputs differ only in
`IPAdmissionPolicy.swift`; added tests are not benchmark target inputs.
Temporary SwiftPM edits select the patched local CIDR. Only its pin is absent
from temporary effective lockfiles; real repository manifests/pins are untouched.

The same official `BenchmarkTool` executable drives every capture directly,
without SwiftPM rebuilding during measurement. Source/binary checks surround
each capture. Only new baseline-storage paths were used. Each metric profile
runs the four variants in both forward and reverse order; exact chronology is
saved in [method metadata](evidence/method.json). No agent-initiated compilation
overlapped timing. Other compiler activity was checked before/after, not
continuously. Background work was not controlled; per-run load and AC-power
state are retained. Two runs do not establish statistical significance.

Full metrics are the nine configured metrics: wall time, throughput, three
malloc counters, object allocations, retains, releases, and retain/release
delta. Timing-only requests wall time and throughput from the same linked
binary with allocation/ARC hooks unrequested; it is not an interposer-free
build. Allocation stacks are disabled. The reference sampling configuration
is unchanged. Original decision cases consume `isAllowed`; projection
controls consume the complete decision. Compare like-for-like cases.
Default discovery remains 174 cases, or 190 with projection controls enabled.

Long address-only, range-only, and opposite-family-only misses were not timed
in this comparison. Their phase-one performance must not be inferred from
the network and mixed-rule results. Neither these Mac timings nor its code
generation should be assumed to apply unchanged to Linux or iOS.

## Evidence

- [Comparison CSV](comparison.csv): individual run p50/p99, sample units, throughput, and ratios.
- [Validation](validation.json): case/metric/sample coverage and allocation/ARC checks.
- [Preservation](preservation.json): original files, refs, staging, and dependency preservation.
- [Example capture](runs/phased-full-1/metadata.json): exact commands, environment, duration, and native-baseline hash.
- [Code-generation summary](evidence/codegen.json): static call sites, not dynamic call counts.
- [Native Linux validation](linux/verification.json) and [code-generation summary](linux/codegen.json): both supported toolchains, with raw build/test logs and assembly retained.
- [Admission source patch](evidence/admission-source.patch.gz) and [CIDR source patch](evidence/cidr-source.patch.gz): reconstruction from the recorded base commits.

Each run includes an untouched compressed native baseline, raw text/Influx
exports, stdout/stderr, normalized summary, and coverage. Evidence includes
all four policy source snapshots, dependency graphs/locks, builds, tests,
assembly, and hashes. Capture scripts record the actual temporary paths and
procedure; they are provenance, not a location-independent CLI. To reconstruct,
apply the patches to isolated copies of the stated base commits, select the
desired policy snapshot, edit the temporary CIDR dependency to the patched
source, and build Release with the recorded toolchain and pins. After a
SwiftPM dependency edit, do not use `--disable-automatic-resolution`, which
can restore the remote checkout instead of the patched source.

Verify the bundle with `shasum -a 256 -c SHA256SUMS` from this directory.
Earlier snapshots and graphs are unchanged. Nothing was staged, committed,
pushed, merged, or tagged.
