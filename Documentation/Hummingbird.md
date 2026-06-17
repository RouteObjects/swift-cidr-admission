# Hummingbird Usage

Hummingbird is built on SwiftNIO and supports middleware. The exact place to get
the immediate peer address depends on the server configuration and request
context used by the application, so keep address selection in the app and pass a
resolver into the middleware.

```swift
import CIDRAdmission
import CIDRNIO
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

Use this for immediate-peer admission, such as allowing only known ingress
proxies, sidecars, load balancers, VPN ranges, or management networks.

Client-origin admission behind proxies should first verify the immediate peer is
trusted, then resolve a trusted client address from headers or PROXY protocol.
That trust-chain resolver is deployment-specific and intentionally outside
`CIDRAdmission`.
