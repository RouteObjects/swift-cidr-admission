# Hummingbird Usage

Hummingbird is built on SwiftNIO and supports middleware. The exact place to get
the immediate peer address depends on the server configuration and request
context used by the application, so keep address selection in the app and pass a
resolver into the middleware.

```swift
import CIDRAdmission
import CIDRNIO
import Foundation
import Hummingbird
import NIOCore

struct IPAdmissionMiddleware<Context>: RouterMiddleware {
    let policy: IPAdmissionPolicy
    let remoteAddress: @Sendable (Request, Context) throws -> SocketAddress?

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard
            let socketAddress = try remoteAddress(request, context),
            let address = try? AnyIPAddress(socketAddress: socketAddress),
            policy.allows(address)
        else {
            return Response(status: .forbidden)
        }

        return try await next(request, context)
    }
}
```

Build the immutable policy before starting the application or event-loop group:

```swift
let files = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .deny,
    allowFile: URL(fileURLWithPath: "/etc/my-service/allow.txt"),
    denyFile: URL(fileURLWithPath: "/etc/my-service/deny.txt")
)
let policy = try IPAdmissionPolicy(fileConfiguration: files)
```

The two inputs are independent, role-neutral RouteObjects IP List Text v1
files. `.required` requires an exact detached `<list-path>.sha256` checksum for
each configured list. `.verifyIfPresent` accepts a missing detached checksum
file for development, but never accepts a present malformed or mismatched
checksum file.
A matching SHA-256 digest shows agreement with the supplied checksum; the
checksum still requires trusted distribution and does not authenticate the
producer or prove file provenance.

Loading is synchronous: it reads, validates any required or present checksum,
parses, and indexes both roles before returning one immutable policy. Do that
work at startup, not from `handle(_:context:next:)` or another event-loop-bound
path. This file-backed list API accepts only local files and has no acquisition,
watching, or hot reload behavior. The legacy single-JSON initializer retains Foundation
URL-loading behavior for source compatibility; pass it a local file URL when
an offline load is required, and never pass it an untrusted or request-derived
URL.

`allows(_:)` takes the indexed Boolean path. Use `decision(for:)` when detailed
logging needs the first matching source `AdmissionRule` and its allow/deny
role.

Use this for immediate-peer admission, such as allowing only known ingress
proxies, sidecars, load balancers, VPN ranges, or management networks.

Client-origin admission behind proxies should first verify the immediate peer is
trusted, then resolve a trusted client address from headers or PROXY protocol.
That trust-chain resolver is deployment-specific and intentionally outside
`CIDRAdmission`.
