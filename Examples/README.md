# Examples

This directory contains runnable examples for `swift-cidr-admission`.

The root `CIDRAdmission` package is intentionally framework-neutral and depends
only on `swift-cidr`. Examples that require additional frameworks live here as
separate Swift packages so those dependencies do not become part of the root
package dependency graph.

## NIOTCPEchoAdmissionServer

`NIOTCPEchoAdmissionServer` demonstrates connection-admission logic in a
SwiftNIO TCP echo server.

Run from the repository root:

```bash
swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer
```

See [NIOTCPEchoAdmissionServer](NIOTCPEchoAdmissionServer/README.md) for custom
policy examples, deny-all experiments, and command-line options.
