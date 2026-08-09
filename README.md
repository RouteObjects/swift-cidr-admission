<h1 align="left">
  <img src="Documentation/Assets/swift-cidr-admission.png" alt="swift-cidr-admission icon" width="75" height="75" valign="middle">
  &nbsp;CIDRAdmission
</h1>

`CIDRAdmission` is a framework-neutral admission-policy package for
[`swift-cidr`](https://github.com/RouteObjects/swift-cidr). It compiles
address, network, and range rules into an `IPAdmissionPolicy` that can be
evaluated against `AnyIPAddress` values.

> [!IMPORTANT]
> `CIDRAdmission` is application-level admission control. Use firewall rules, cloud security
> groups, load balancer ACLs, `pf`, `iptables`, or `nftables` first. Use this
> package for service-owned policy, [defense-in-depth](https://csrc.nist.gov/glossary/term/defense_in_depth), local deployments, or
> auditable last checks inside a Swift server process.

## Package Dependency

```swift
.package(
    url: "https://github.com/RouteObjects/swift-cidr.git",
    .upToNextMinor(from: "0.5.0")
),
.package(
    url: "https://github.com/RouteObjects/swift-cidr-admission.git",
    .upToNextMinor(from: "0.2.0")
)
```

```swift
.product(name: "CIDR", package: "swift-cidr"),
.product(name: "CIDRAdmission", package: "swift-cidr-admission")
```

`CIDRAdmission` uses `swift-cidr` as its IP/range authority and Swift Crypto for
detached SHA-256 verification. For SwiftNIO `SocketAddress` conversion, also
import `CIDRNIO` from `swift-cidr`.

## Migrating from 0.1

`0.2.0` intentionally makes source-breaking changes where policy rules are
exposed or matched:

- `IPAdmissionPolicy.allow` and `.deny` change from `[AnyIPNetwork]` to
  `[AdmissionRule]` so they can preserve address, network, and range inputs.
- `AdmissionDecisionReason.matched(ruleSet:network:)` changes to
  `.matched(ruleSet:rule:)`.

The legacy `IPAdmissionPolicy(allow:deny:defaultAction:)` initializer still
accepts `[AnyIPNetwork]`, and the JSON wire shape remains the same CIDR-only
`defaultAction` / `allow` / `deny` document. Code that only constructs policies
through those interfaces may not need source changes; code that reads the
public rule arrays or pattern-matches detailed decisions must migrate.

The 0.2 package also requires `swift-cidr` 0.5.x and adds Swift Crypto 4.x for
detached SHA-256 validation. Consumers pinned to older `swift-cidr` releases
must update their dependency requirements during migration.

If a 0.1 consumer is not ready to migrate, keep its dependency pinned as:

```swift
.package(
    url: "https://github.com/RouteObjects/swift-cidr-admission.git",
    .upToNextMinor(from: "0.1.0")
)
```

For a pre-1.0 package, that requirement excludes `0.2.0`. Change the lower
bound to `0.2.0` only after reviewing the source migration above.

## Legacy JSON Configuration

Policy is intended to come from deployment configuration, not hardcoded source
lists.

```json
{
  "defaultAction": "deny",
  "allow": ["10.0.0.0/8", "2001:db8::/32"],
  "deny": ["10.0.5.13/32"]
}
```

`deny` rules win over overlapping `allow` rules.

This single-document JSON interface remains supported for compatibility and
small policies. Its `allow` and `deny` strings are CIDR networks. File-backed
policy uses the role-neutral text format below and additionally accepts bare
addresses and inclusive address ranges.

`0.0.0.0/0` means all IPv4 addresses, and `::/0` means all IPv6 addresses. To
allow both address families, include both networks. Deny rules still win, so an
allow-all policy can still carve out rejected ranges.

## File-Backed Policy

A file-backed policy assigns two independent, role-neutral **RouteObjects IP
List Text v1** files as allow and deny inputs. Neither file contains an allow or
deny marker; `IPAdmissionPolicyFileConfiguration` assigns the role. An omitted
file URL means an empty role, while a configured missing, unreadable, non-file,
or invalid URL makes the complete policy load fail.

The text grammar is deliberately small and auditable:

- UTF-8, with an optional BOM only at the beginning of the file.
- LF or CRLF line endings; the final newline is optional. Other ASCII or
  Unicode line separators are rejected.
- Blank lines, full-line `#` comments, and trailing `#` comments are ignored.
- Every other line is exactly one CIDR network, same-family inclusive
  `lower...upper` range, or bare address. A bare address is one host.
- Mixed-family or reversed ranges, CIDR-qualified range endpoints, extra
  columns, malformed values, and invalid UTF-8 fail the entire load.
- A zero-byte file is a valid empty list.

Choose integrity behavior explicitly for every file-backed policy:

```swift
import CIDRAdmission
import Foundation

let fileConfiguration = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .deny,
    allowFile: URL(fileURLWithPath: "/etc/my-service/allow.txt"),
    denyFile: URL(fileURLWithPath: "/etc/my-service/deny.txt")
)
let policy = try IPAdmissionPolicy(fileConfiguration: fileConfiguration)
```

The role assignment makes an explicit allowlist or blocklist equally small:

```swift
let allowlist = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .deny,
    allowFile: URL(fileURLWithPath: "/etc/my-service/allow.txt"),
    denyFile: nil
)

let blocklist = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .allow,
    allowFile: nil,
    denyFile: URL(fileURLWithPath: "/etc/my-service/deny.txt")
)
```

An allowlist denies anything not explicitly allowed. A blocklist allows
anything not explicitly denied. A policy may also configure both files; deny
rules always take precedence.

- `.required` requires a valid detached `<list-path>.sha256` file for every
  configured list. This is the production recommendation.
- `.verifyIfPresent` permits a missing detached checksum file, but a present
  malformed, filename-mismatched, or digest-mismatched checksum file still
  fails the load.

Each detached checksum contains exactly one line:

```text
<64 lowercase hexadecimal SHA-256 digits><two spaces><list basename><LF>
```

When a checksum is required or present, Admission hashes the exact deployed
list bytes before parsing those same bytes; line endings and a final line feed
therefore matter. Both roles are read, conditionally checksum-validated,
parsed, and compiled into temporary state, and no policy is returned unless
both succeed. Each path is opened once, checked as a regular file, and read
through that same pinned descriptor; a symbolic link is accepted only when its
opened target is regular.

A matching digest shows that the loaded bytes agree with the supplied checksum.
It can detect accidental corruption or an uncoordinated edit only when the
checksum itself arrives through a trusted channel. It does not detect a
coordinated replacement of both files, authenticate the producer, prove file
provenance, or bind the allow and deny files into one deployment generation.

File loading is synchronous. Construct the policy during application startup
or otherwise away from server event loops, then share the immutable policy with
request or connection handlers. The file-backed list API accepts local file
URLs only and does not fetch, watch, or hot reload lists. The legacy JSON
`contentsOf:` initializer retains Foundation URL-loading behavior for source
compatibility; never pass it an untrusted or user-controlled URL, and use a
local file URL when an offline load is required.

### Security maturity and trust boundary

The 0.2 release delivers maturity levels 1 through 4: separate allow/deny
files, representation-aware auditable rules with private exact-coverage
indexes, detached checksum verification, descriptor-pinned local reads, and
all-or-nothing policy construction. Level 5 producer authenticity and Level 6
runtime audit metrics/logging are deferred.

A matching SHA-256 digest shows that the loaded bytes agree with the supplied
checksum; the checksum still needs a trusted distribution channel. It does not
detect coordinated replacement, authenticate who produced the files, or bind
the allow and deny files to one deployment generation. Feed fetching, signature
or provenance verification, deployment orchestration, file watching/hot reload,
and audit metrics remain outside `CIDRAdmission` 0.2. Applications must
establish those trust and lifecycle controls around policy construction.

### Offline cidrmerge pipeline

[`cidrmerge`](https://github.com/RouteObjects/cidrmerge) is a role-neutral,
offline exact-coverage compiler. Run it once per role; acquisition and
deployment remain separate operational steps:

```bash
cidrmerge --input-format searchbot --raw --representation ranges \
  --checksum --output allow.txt saved-crawler-prefixes.json

cidrmerge --input-format text --raw --representation ranges \
  --checksum --output deny.txt blocked-prefixes.txt
```

The two outputs are IP List Text v1 inputs. `--representation cidr` is also
valid and must produce the same admission decisions because both
representations preserve exact address coverage. cidrmerge does not assign
roles, set `defaultAction`, download feeds, or emit admission-policy JSON.

## Usage

```swift
import CIDR
import CIDRAdmission
import Foundation

enum ExampleError: Error {
    case invalidAddress
}

let configURL = URL(fileURLWithPath: "/etc/my-service/ip-admission.json")
let policy = try IPAdmissionPolicy(contentsOf: configURL)

guard let address = AnyIPAddress("10.0.5.12") else {
    throw ExampleError.invalidAddress
}

if policy.allows(address) {
    // Continue with the request or connection.
} else {
    // Reject the request or connection.
}
```

`allows(_:)` uses private IPv4/IPv6 exact-coverage indexes for the fast Boolean
path. Use `decision(for:)` when diagnostics need the first matching source
`AdmissionRule` and its allow/deny role; source order and rule kind are retained
for that detailed path.

## SwiftNIO-Based Servers

Use `CIDRNIO` to convert the immediate peer `SocketAddress` into
`AnyIPAddress`, then evaluate the framework-neutral policy.

```swift
import CIDRAdmission
import CIDRNIO

let address = try AnyIPAddress(socketAddress: remoteAddress)

guard policy.allows(address) else {
    // Reject the request or close the connection.
    return
}
```

This checks the immediate peer. If a service is behind a proxy, load balancer,
or ingress, the immediate peer is usually that infrastructure component. Client
origin policy requires separate trusted-proxy resolution before evaluating the
resulting address.

## Framework Examples

- [Vapor](Documentation/Vapor.md)
- [Hummingbird](Documentation/Hummingbird.md)

## Runnable SwiftNIO Example

A runnable SwiftNIO echo server example lives in
[Examples/NIOTCPEchoAdmissionServer](Examples/NIOTCPEchoAdmissionServer/README.md).
It is nested so SwiftNIO stays out of the root package dependency graph while
still giving users an immediate way to try connection admission locally.

From the repository root:

```bash
swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer
```

## Benchmarking

Benchmark tooling lives in the separate [Benchmarks](Benchmarks/README.md)
package so `CIDRAdmission` users do not resolve benchmark-only dependencies.

```bash
./scripts/benchmarks.sh build
./scripts/benchmarks.sh list
./scripts/benchmarks.sh run --filter '^policy\.lookup\..*\.500$' --no-progress --time-units nanoseconds
```

The benchmark matrix covers policy sizes from `0` to `10,000` source rules.
The checked-in chart records the 0.1 linear-scan baseline; the benchmark
package README separately records the dated 0.2.0 measurements for
indexed lookup, detailed decisions, file loading, and checksum verification.
