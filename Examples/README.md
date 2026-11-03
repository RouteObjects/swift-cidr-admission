# Examples

This directory contains runnable examples for `swift-cidr-admission`.

The root `CIDRAdmission` package is intentionally framework-neutral and depends
only on `swift-cidr` for IP/CIDR behavior and Swift Crypto for detached SHA-256
verification. Examples that require additional frameworks live here as
separate Swift packages so their framework-specific targets and direct
dependencies remain in the example manifests rather than the root manifest.

## NIOTCPEchoAdmissionServer

`NIOTCPEchoAdmissionServer` demonstrates connection-admission logic in a
SwiftNIO TCP echo server.

Run from the repository root:

```bash
swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer
```

See [NIOTCPEchoAdmissionServer](NIOTCPEchoAdmissionServer/README.md) for custom
policy examples, deny-all experiments, and command-line options.

## NIOTCPEgressAdmissionClient

`NIOTCPEgressAdmissionClient` demonstrates destination admission before socket
connection, using a SwiftNIO connect hook and async/await application I/O.
It loads allow/deny list files with required detached checksums and checks
every attempted destination, including resolved hostname candidates.

With the echo server running, run from the repository root in another terminal:

```bash
swift run --package-path Examples/NIOTCPEgressAdmissionClient NIOTCPEgressAdmissionClient
```

See [NIOTCPEgressAdmissionClient](NIOTCPEgressAdmissionClient/README.md) for custom
list files, checksum generation, deny-before-connect experiments, and the
numbered integration comments. The server and client demonstrate separate
ingress and egress policies; neither replaces network firewall controls.
