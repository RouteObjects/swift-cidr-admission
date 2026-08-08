# NIOTCPEchoAdmissionServer

`NIOTCPEchoAdmissionServer` is a small SwiftNIO executable example adapted from
SwiftNIO's echo server. It demonstrates connection-admission logic at the
accepted-channel boundary before the echo pipeline is installed.

The server source includes numbered `Integration point` comments that show the
admission flow step by step for readers learning how to adapt the pattern.

The bundled policy defaults to `defaultAction: "deny"` and allows only
`127.0.0.1/32`, so local `nc` experiments work immediately when the server binds
to its default `127.0.0.1` address.

## Run

```bash
swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer
```

In another terminal:

```bash
nc 127.0.0.1 8765
```

Then type a line and press Return:

```text
hello
```

Expected output is the echoed line:

```text
hello
```

## Custom Policy

Create a JSON policy and pass it with `--policy`:

```bash
cat >/tmp/ip-admission.json <<'JSON'
{
  "defaultAction": "deny",
  "allow": ["127.0.0.1/32"],
  "deny": []
}
JSON

swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer --policy /tmp/ip-admission.json
```

The example's small `--policy` option intentionally retains the legacy
single-JSON path. An application using the file-policy API can replace the
startup load with two independent, role-neutral RouteObjects IP List Text v1
files:

```swift
let files = IPAdmissionPolicyFileConfiguration(
    checksumPolicy: .required,
    defaultAction: .deny,
    allowFile: URL(fileURLWithPath: "/etc/my-service/allow.txt"),
    denyFile: URL(fileURLWithPath: "/etc/my-service/deny.txt")
)
let policy = try IPAdmissionPolicy(fileConfiguration: files)
```

`.required` expects an exact detached `allow.txt.sha256` or `deny.txt.sha256`
beside each configured list. `.verifyIfPresent` is useful for development when
a detached checksum file may be absent, but any checksum file that exists must
be valid and match the exact list bytes. SHA-256 provides integrity, not
authenticity or provenance.

This initializer performs synchronous file I/O, verification, parsing, and
index construction. Keep it at startup, as this example does, and not in an
accepted-channel initializer or on an event loop. `CIDRAdmission` does not
download lists, watch files, or hot reload policy.

To prepare the two files offline, run
[`cidrmerge`](https://github.com/RouteObjects/cidrmerge) independently for the
allow and deny roles:

```bash
cidrmerge --input-format searchbot --raw --representation ranges \
  --checksum --output allow.txt saved-crawler-prefixes.json

cidrmerge --input-format text --raw --representation ranges \
  --checksum --output deny.txt blocked-prefixes.txt
```

The list bytes do not encode their role; the typed admission configuration does.
At runtime, `allows(_:)` uses private exact-coverage indexes. The example calls
`decision(for:)` so logs retain the first matching source `AdmissionRule`,
including whether it was an address, network, or range.

The policy evaluates the immediate peer address from SwiftNIO's
`Channel.remoteAddress`. If the service is behind a proxy, load balancer, or
ingress, the immediate peer is usually that infrastructure component. Client
origin admission still belongs in framework or application middleware after
trusted-proxy resolution.

## Deny-All Experiment

Use an empty allow list with a deny default to see the server reject local
connections before installing the echo handlers:

```bash
cat >/tmp/deny-all-admission.json <<'JSON'
{
  "defaultAction": "deny",
  "allow": [],
  "deny": []
}
JSON

swift run --package-path Examples/NIOTCPEchoAdmissionServer NIOTCPEchoAdmissionServer --policy /tmp/deny-all-admission.json
```

In another terminal:

```bash
nc 127.0.0.1 8765
```

Type `hello` and press Return. The connection should close without echoing
`hello`.

## Options

```text
--host <host>      Bind address. Defaults to 127.0.0.1.
--port <port>      Bind port. Defaults to 8765.
--policy <path>    JSON admission policy. Defaults to bundled 127.0.0.1/32 allow policy.
-h, --help         Show help.
```
