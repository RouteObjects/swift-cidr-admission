# ARM64 Code-Generation Evidence

Disassembled from the release benchmark build on Apple M1 Max with Apple
Swift 6.3.3 and Xcode 26.6. The admission and CIDR library sources were not
edited. [provenance.json](provenance.json) records the object hashes, source
revisions, compiler, and exact `llvm-objdump` commands.

- `admission-rule-contains.s`: production `AdmissionRule.contains(_:)` retains
  calls to `PrefixLength.maximum` and the generic `IPPrefix.contains(address:)`.
- `ip-prefix-contains.s`: that generic body retains associated-type and
  conformance witness lookups, type metadata calls, and indirect protocol calls.
- `any-network-contains.s`: the family-erased API's public forwarding symbols
  and merged implementation. The shared arithmetic body has explicit IPv4 and
  IPv6 paths without those generic witness/metadata calls. Compiler function
  merging aliases the public address and subnet entry points.

These observations explain the current call-shape comparison; they do not
establish identical code generation on other compilers, architectures, or
build configurations. The network-only benchmark alternatives are not
production fixes.
