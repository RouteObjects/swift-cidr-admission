# Vapor Usage

Vapor exposes the immediate peer as `Request.remoteAddress`. That address may be
the reverse proxy or load balancer rather than the original client. Use this
middleware for immediate-peer admission, such as allowing only known ingress
proxies or management networks.

```swift
import CIDRAdmission
import CIDRNIO
import Foundation
import Vapor

struct IPAdmissionMiddleware: AsyncMiddleware {
    let policy: IPAdmissionPolicy

    func respond(
        to request: Request,
        chainingTo next: AsyncResponder
    ) async throws -> Response {
        let address = try AnyIPAddress(socketAddress: request.remoteAddress)

        guard policy.allows(address) else {
            throw Abort(.forbidden)
        }

        return try await next.respond(to: request)
    }
}
```

Register it early in the middleware chain:

```swift
let files = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .deny,
    allowFile: URL(fileURLWithPath: "/etc/my-service/allow.txt"),
    denyFile: URL(fileURLWithPath: "/etc/my-service/deny.txt")
)
let policy = try IPAdmissionPolicy(fileConfiguration: files)

app.middleware.use(IPAdmissionMiddleware(policy: policy), at: .beginning)
```

`allow.txt` and `deny.txt` are independent, role-neutral RouteObjects IP List
Text v1 files; the configuration assigns their roles. In `.required` mode,
each configured list needs an exact detached `<list-path>.sha256` checksum.
Use `.verifyIfPresent` only when development should permit a missing detached
checksum file; any checksum file that is present must still be valid and match
the exact list bytes.

The file initializer performs synchronous file I/O, checksum verification,
parsing, and index construction. Call it once during application startup, not
from `respond(to:chainingTo:)` or another event-loop-bound request path. This
file-backed list API accepts only local files and does not download, watch, or
hot reload them. The legacy single-JSON `IPAdmissionPolicy(contentsOf:)`
initializer retains Foundation URL-loading behavior for source compatibility;
never pass it an untrusted or request-derived URL, and use a local file URL when
an offline load is required.

For Boolean admission, `allows(_:)` uses private family-partitioned coverage
indexes. Use `decision(for:)` when logs or audit diagnostics need the first
matching source `AdmissionRule` and its allow/deny role.

Client-origin admission behind proxies should first verify the immediate peer is
a trusted proxy, then resolve a trusted client address from the deployment's
chosen forwarding mechanism. That resolver is intentionally outside
`CIDRAdmission`.
