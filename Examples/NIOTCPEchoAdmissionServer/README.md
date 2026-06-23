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
