# cidrmerge Pipeline Acceptance

This nested package validates the documented artifact boundary between the
independent `cidrmerge` producer and `CIDRAdmission` consumer. It is not a
production dependency and does not add `cidrmerge` to the admission library's
package graph.

From the `swift-cidr-admission` repository root, run:

```bash
CIDRMERGE_PACKAGE="../cidrmerge" ./scripts/check-cidrmerge-pipeline.sh
```

The script builds the supplied local `cidrmerge` checkout, generates allow and
deny artifacts independently in range and CIDR representations, verifies their
exact detached SHA-256 checksum records with system tooling, and loads every
representation pairing using `IPAdmissionChecksumPolicy.required`.

The public-only Swift executable checks IPv4/IPv6 boundaries, deny-first
decisions, omitted and explicit-empty roles, source-rule representation, and
fixed-seed agreement between indexed `allows(_:)` and detailed
`decision(for:)`. The shell layer also proves deterministic bytes, equivalent
exact coverage, checksum failure classifications, atomic two-role failure, and
that cidrmerge JSON is not the IP List Text v1 admission interchange.

All files are generated under a temporary directory. The acceptance path does
not download vendor data or assign allow/deny roles inside `cidrmerge`.

This nested package keeps its own resolved dependency graph as an independent
external-consumer check. Its compatible transitive versions may differ from
the root and benchmark packages; CI resolves and diff-checks the root and
pipeline locks independently. The benchmark lock records the Swift 6.3
full-metrics manifest and is verified under that canonical toolchain because
Benchmark 1.35 deliberately selects a different dependency graph on Swift 6.1
and 6.2.
