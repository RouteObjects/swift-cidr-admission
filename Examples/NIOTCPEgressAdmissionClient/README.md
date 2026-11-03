# NIOTCPEgressAdmissionClient

An async/await SwiftNIO client that checks destination IP admission **before
socket connection**, then sends one line to the companion
[echo server](../NIOTCPEchoAdmissionServer/README.md). This is a separate Swift
package so its NIO-specific implementation and direct framework dependencies
stay outside the root library and manifest.

Numbered `Integration point` comments in
[Client.swift](Sources/EgressClientExample/Client.swift) and
[EgressAdmissionHandler.swift](Sources/EgressClientExample/EgressAdmissionHandler.swift)
trace policy loading, handler installation, destination conversion, decision,
rejection/forwarding, connection, and async I/O.

The implementation lives in the internal `EgressClientExample` target so tests
do not link the executable's entry point. It is not a public library product.

## Run

From the repository root, start the existing server:

```bash
swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer
```

In another terminal, also from the repository root:

```bash
swift run --package-path Examples/NIOTCPEgressAdmissionClient NIOTCPEgressAdmissionClient
```

The client prints `hello` to stdout and exits successfully. Admission diagnostics
go to stderr. The bundled, checksum-verified list allows only `127.0.0.1/32` and
`::1/128`; the default host is `127.0.0.1` and the default TCP port is `8765`.

Open this directory's `Package.swift` separately in Xcode and select **My Mac**
to run it. The package declares macOS 15 and iOS 18 for consistent indexing;
iOS validation is compile-only. Swift 6.2 or later is required.

## Allow and Deny Files

The client uses `IPAdmissionPolicyFileConfiguration` with `.required` detached
checksums and `.deny` as its default action. It loads and verifies all configured
files once at startup, before DNS resolution or connection setup. It does not
download, watch, or reload files.

Rules use RouteObjects IP List Text v1: one address, CIDR, or inclusive range
per line, with optional comments. The file itself does not encode an allow or
deny role; the command-line option supplies the role.

Prepare a custom policy:

```bash
mkdir -p /tmp/egress-policy
printf '127.0.0.1/32\n::1/128\n' > /tmp/egress-policy/allow.txt
(
    cd /tmp/egress-policy
    shasum -a 256 allow.txt > allow.txt.sha256
)

swift run --package-path Examples/NIOTCPEgressAdmissionClient NIOTCPEgressAdmissionClient \
    --allow-file /tmp/egress-policy/allow.txt --message 'custom policy'
```

On Linux, `sha256sum allow.txt > allow.txt.sha256` is an equivalent checksum
command. Run it in the file's directory so the sidecar names `allow.txt`, not
an absolute path. Recalculate the checksum whenever the list bytes change.
Missing, malformed, or mismatched checksums cause startup to fail without
resolving a hostname or attempting a connection.

A matching SHA-256 checksum establishes agreement with the supplied checksum,
not producer authenticity. Both list and checksum require trusted distribution.
[`cidrmerge`](https://github.com/RouteObjects/cidrmerge) can also generate these
lists and sidecars offline; compile allow and deny inputs independently.

**Supplying either custom file replaces the bundled policy entirely.** An
omitted role is empty. A deny file without an allow file therefore denies every
destination under the fixed deny default. Deny rules always take precedence.

## Deny Before Connect

Keep the echo server running and add a deny rule for the default destination:

```bash
printf '127.0.0.1/32\n' > /tmp/egress-policy/deny.txt
(
    cd /tmp/egress-policy
    shasum -a 256 deny.txt > deny.txt.sha256
)

swift run --package-path Examples/NIOTCPEgressAdmissionClient NIOTCPEgressAdmissionClient \
    --allow-file /tmp/egress-policy/allow.txt \
    --deny-file /tmp/egress-policy/deny.txt
```

The client logs the denied destination and rule, emits no echo, and exits
nonzero. The denied connect operation is not forwarded to the socket. The
server should see no new connection from this attempt.

## Hostnames and Connection Attempts

```bash
swift run --package-path Examples/NIOTCPEgressAdmissionClient NIOTCPEgressAdmissionClient \
    --host localhost --message 'hostname example'
```

SwiftNIO resolves hostnames and applies Happy Eyeballs. The handler checks the
concrete `SocketAddress` supplied to **each** `connect` operation, including
fallback candidates. One denied candidate does not prevent another allowed
candidate from succeeding. If all candidates fail, NIO reports a connection
error; the per-candidate diagnostics distinguish policy denials from other
failures. Only the supplied destination IP is evaluated, not the hostname.

The existing server defaults to IPv4 loopback. To try `--host ::1`, run the
server with `--host ::1` and an ingress JSON policy that allows `::1/128` as
described in its README. Client egress and server ingress are independent.

## Async/Await Boundary

Connection setup uses async `ClientBootstrap.connect`; application I/O uses
`NIOAsyncChannel<String, String>` and `executeThenClose`. The latter closes the
channel on success or failure. The response iterator is owned by one task.

NIO's `ChannelOutboundHandler.connect(context:to:promise:)` is a synchronous
event-loop callback. This small boundary forwards the original promise when
allowed, or fails it and closes the channel when rejected. It performs no
policy-file I/O, DNS lookup, or asynchronous task creation. Unsupported address
conversions fail closed. Other outbound operations use NIO's default forwarding;
there are no policy checks per write, packet, or byte.

Connection and response deadlines are each five seconds. NIO's future-to-async
connection bridge does not automatically cancel an in-flight connect: it may
settle within its timeout. Cancellation is checked before connecting and again
before sending; a cancelled connection closes without application data. During
the exchange, cancellation or deadline expiry terminates the scoped channel.

Messages are single UTF-8 lines, at most 64 KiB excluding the LF delimiter.
Embedded CR/LF, oversized or invalid UTF-8 responses, incomplete EOF, and echoes
that differ from the sent message are errors. Empty messages are allowed.

This demonstrates application-level defense in depth, not a network egress
firewall. The policy does not authorize ports or hostnames, authenticate TLS
peers, restrict DNS traffic, or inspect ultimate destinations behind proxies.
It governs only connection attempts made through this configured bootstrap.

## Options and Tests

```text
--host <host>        Literal IP or hostname. Default: 127.0.0.1.
--port <port>        TCP port (1...65535). Default: 8765.
--message <text>     Single UTF-8 line, up to 64 KiB. Default: hello.
--allow-file <path>  Local allow list; requires <path>.sha256.
--deny-file <path>   Local deny list; requires <path>.sha256.
-h, --help          Show help without loading policy or connecting.
```

```bash
swift test --package-path Examples/NIOTCPEgressAdmissionClient
swift test --package-path Examples/NIOTCPEgressAdmissionClient -c release
```

Tests use NIOEmbedded probes, injected DNS responses, and ephemeral IPv4/IPv6
loopback listeners. They do not contact public hosts or depend on public DNS.
