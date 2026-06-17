# CIDRAdmission

`CIDRAdmission` is a framework-neutral admission-policy package for
[`swift-cidr`](../Example%20Framework/Packages/swift-cidr/README.md). It turns
external allow/deny CIDR configuration into a compiled `IPAdmissionPolicy` that
can be evaluated against `AnyIPAddress` values.

> [!IMPORTANT]
> `CIDRAdmission` is application-level admission control. Use firewall rules, cloud security
> groups, load balancer ACLs, `pf`, `iptables`, or `nftables` first. Use this
> package for service-owned policy, [defense-in-depth](https://csrc.nist.gov/glossary/term/defense_in_depth), local deployments, or
> auditable last checks inside a Swift server process.

## Package Dependency

```swift
.package(path: "../swift-cidr-admission")
```

```swift
.product(name: "CIDRAdmission", package: "swift-cidr-admission")
```

`CIDRAdmission` depends only on `swift-cidr`. For SwiftNIO `SocketAddress`
conversion, also import `CIDRNIO` from `swift-cidr`.

## Configuration

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

## Usage

```swift
import CIDR
import CIDRAdmission
import Foundation

let configURL = URL(fileURLWithPath: "/etc/my-service/ip-admission.json")
let policy = try IPAdmissionPolicy(contentsOf: configURL)

let address = AnyIPAddress("10.0.5.12")!

if policy.allows(address) {
    // Continue with the request or connection.
} else {
    // Reject the request or connection.
}
```

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

## Executable Example

- [NIOTCPEchoAdmissionServer](Documentation/NIOTCPEchoAdmissionServer.md)
