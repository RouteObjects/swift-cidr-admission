# Vapor Usage

Vapor exposes the immediate peer as `Request.remoteAddress`. That address may be
the reverse proxy or load balancer rather than the original client. Use this
middleware for immediate-peer admission, such as allowing only known ingress
proxies or management networks.

```swift
import CIDRAdmission
import CIDRNIO
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
let configURL = URL(fileURLWithPath: "/etc/my-service/ip-admission.json")
let policy = try IPAdmissionPolicy(contentsOf: configURL)

app.middleware.use(IPAdmissionMiddleware(policy: policy), at: .beginning)
```

Client-origin admission behind proxies should first verify the immediate peer is
a trusted proxy, then resolve a trusted client address from the deployment's
chosen forwarding mechanism. That resolver is intentionally outside
`CIDRAdmission`.
