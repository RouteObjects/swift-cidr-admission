#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
#
# This source file is part of the swift-cidr-admission project.
#
# Copyright (c) 2026 Craig A. Munro
#
# Licensed under the Apache License, Version 2.0.
# See the LICENSE file for details.
#
# SPDX-License-Identifier: Apache-2.0
#
#===----------------------------------------------------------------------===#

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
CONSUMER_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cidr-admission-consumer.XXXXXX")"

cleanup() {
    rm -rf -- "${CONSUMER_ROOT}"
}
trap cleanup EXIT

fail() {
    printf 'CIDRAdmission consumer check: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_detached_checksum() {
    local source="$1"
    printf '%s  %s\n' "$(sha256_file "${source}")" "$(basename -- "${source}")" \
        >"${source}.sha256"
}

mkdir -p "${CONSUMER_ROOT}/Sources/AdmissionConsumer" "${CONSUMER_ROOT}/Fixtures"

# Build an actual external package so release validation catches accidental changes to
# product names, public access levels, initializer labels, and transitive package resolution.
cat >"${CONSUMER_ROOT}/Package.swift" <<EOF
// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AdmissionConsumer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "swift-cidr-admission", path: "${PACKAGE_ROOT}"),
        .package(
            url: "https://github.com/RouteObjects/swift-cidr.git",
            .upToNextMinor(from: "0.5.0")
        ),
    ],
    targets: [
        .executableTarget(
            name: "AdmissionConsumer",
            dependencies: [
                .product(name: "CIDRAdmission", package: "swift-cidr-admission"),
                .product(name: "CIDR", package: "swift-cidr"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
EOF

cat >"${CONSUMER_ROOT}/Sources/AdmissionConsumer/main.swift" <<'EOF'
import CIDR
import CIDRAdmission
import Foundation

private enum ConsumerError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ConsumerError.failed(message) }
}

private func address(_ text: String) throws -> AnyIPAddress {
    guard let value = AnyIPAddress(text) else {
        throw ConsumerError.failed("invalid fixture address: \(text)")
    }
    return value
}

private func network(_ text: String) throws -> AnyIPNetwork {
    guard let value = AnyIPNetwork(text) else {
        throw ConsumerError.failed("invalid fixture network: \(text)")
    }
    return value
}

private func range(_ text: String) throws -> AnyIPAddressRange {
    guard let value = AnyIPAddressRange(text) else {
        throw ConsumerError.failed("invalid fixture range: \(text)")
    }
    return value
}

@main
private enum AdmissionConsumer {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ConsumerError.failed("expected fixture directory")
        }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

        // Preserve the focused legacy surface that existing 0.1 consumers use. This is an
        // executable compatibility probe, not a claim of complete 0.1 source compatibility.
        let legacy = IPAdmissionPolicy(
            allow: [try network("192.0.2.0/24")],
            deny: [try network("192.0.2.128/25")],
            defaultAction: .deny
        )
        try require(legacy.allows(try address("192.0.2.1")), "legacy allow network failed")
        try require(!legacy.allows(try address("192.0.2.200")), "legacy deny-first failed")

        let json = Data(
            #"{"defaultAction":"allow","allow":["198.51.100.0/24"],"deny":["198.51.100.128/25"]}"#.utf8
        )
        let decoded = try IPAdmissionPolicy(jsonData: json)
        try require(decoded.allows(try address("198.51.100.1")), "legacy JSON allow failed")
        try require(!decoded.allows(try address("198.51.100.200")), "legacy JSON deny failed")
        try require(decoded.allows(try address("203.0.113.1")), "legacy JSON default failed")

        let legacyJSONURL = fixtures.appendingPathComponent("legacy.json")
        let decodedFromFile = try IPAdmissionPolicy(contentsOf: legacyJSONURL)
        try require(
            decodedFromFile.allows(try address("198.51.100.1")),
            "legacy JSON file allow failed"
        )

        let configured = try IPAdmissionPolicy(
            configuration: IPAdmissionPolicyConfiguration(
                defaultAction: .deny,
                allow: ["2001:db8:1::/48"]
            )
        )
        try require(
            configured.allows(try address("2001:db8:1::1")),
            "legacy typed configuration failed"
        )

        // Compile and execute the complete public programmatic rule surface so the
        // release gate catches access-level or associated-value regressions outside @testable.
        let programmatic = IPAdmissionPolicy(
            allowRules: [
                .address(try address("192.0.2.10")),
                .network(try network("198.51.100.0/31")),
                .range(try range("2001:db8::1...2001:db8::3")),
            ],
            denyRules: [
                .range(try range("203.0.113.1...203.0.113.3")),
                .network(try network("203.0.113.0/30")),
            ],
            defaultAction: .deny
        )
        try require(
            programmatic.allows(try address("192.0.2.10")),
            "programmatic address rule failed"
        )
        try require(
            programmatic.allows(try address("198.51.100.1")),
            "programmatic network rule failed"
        )
        try require(
            programmatic.allows(try address("2001:db8::2")),
            "programmatic range rule failed"
        )
        switch programmatic.decision(for: try address("203.0.113.2")) {
        case .deny(reason: .matched(ruleSet: .deny, rule: .range(let matched))):
            try require(
                matched.description == "203.0.113.1...203.0.113.3",
                "programmatic decision returned the wrong first source rule"
            )
        default:
            throw ConsumerError.failed("programmatic decision did not preserve first source rule")
        }

        let required = try IPAdmissionPolicy(
            fileConfiguration: IPAdmissionPolicyFileConfiguration(
                checksumPolicy: .required,
                defaultAction: .deny,
                allowFile: fixtures.appendingPathComponent("allow.txt"),
                denyFile: fixtures.appendingPathComponent("deny.txt")
            )
        )
        try require(required.allows(try address("203.0.113.1")), "required checksum allow failed")
        try require(!required.allows(try address("203.0.113.2")), "required checksum deny failed")
        try require(
            required.allows(try address("198.51.100.1")),
            "required checksum network rule failed"
        )
        try require(
            !required.allows(try address("2001:db8::3")),
            "required checksum IPv6 deny network failed"
        )
        try require(!required.allows(try address("203.0.113.9")), "required checksum default failed")

        switch required.decision(for: try address("203.0.113.2")) {
        case .deny(reason: .matched(ruleSet: .deny, rule: .address(let matched))):
            try require(
                matched.addressLiteral == "203.0.113.2",
                "detailed decision returned the wrong source address rule"
            )
        default:
            throw ConsumerError.failed("detailed decision did not preserve the deny address rule")
        }

        let opportunistic = try IPAdmissionPolicy(
            fileConfiguration: IPAdmissionPolicyFileConfiguration(
                checksumPolicy: .verifyIfPresent,
                defaultAction: .deny,
                allowFile: fixtures.appendingPathComponent("unsigned-allow.txt")
            )
        )
        try require(
            opportunistic.allows(try address("2001:db8::2")),
            "verifyIfPresent did not accept a missing checksum"
        )
        try require(
            !opportunistic.allows(try address("2001:db8::4")),
            "verifyIfPresent default action failed"
        )

        try Data("203.0.113.1...203.0.113.4\n".utf8).write(
            to: fixtures.appendingPathComponent("allow.txt"),
            options: .atomic
        )
        do {
            _ = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .required,
                    allowFile: fixtures.appendingPathComponent("allow.txt")
                )
            )
            throw ConsumerError.failed("tampered required-checksum input unexpectedly loaded")
        } catch IPAdmissionPolicyFileLoadError.checksumDigestMismatch(let ruleSet, _, _, _, _) {
            try require(ruleSet == .allow, "checksum mismatch reported the wrong role")
        }

        print("CIDRAdmission external consumer checks passed.")
    }
}
EOF

printf '%s\n' \
    '203.0.113.1...203.0.113.3' \
    '198.51.100.0/31' \
    >"${CONSUMER_ROOT}/Fixtures/allow.txt"
printf '%s\n' \
    '203.0.113.2' \
    '2001:db8::/126' \
    >"${CONSUMER_ROOT}/Fixtures/deny.txt"
printf '%s\n' '2001:db8::1...2001:db8::3' >"${CONSUMER_ROOT}/Fixtures/unsigned-allow.txt"
printf '%s\n' \
    '{"defaultAction":"allow","allow":["198.51.100.0/24"],"deny":["198.51.100.128/25"]}' \
    >"${CONSUMER_ROOT}/Fixtures/legacy.json"
write_detached_checksum "${CONSUMER_ROOT}/Fixtures/allow.txt"
write_detached_checksum "${CONSUMER_ROOT}/Fixtures/deny.txt"

(
    cd "${CONSUMER_ROOT}"
    swift package resolve
    swift build --product AdmissionConsumer
)

consumer_binary="$(swift build --package-path "${CONSUMER_ROOT}" --show-bin-path)/AdmissionConsumer"
[[ -x "${consumer_binary}" ]] || fail "external consumer executable was not built"
"${consumer_binary}" "${CONSUMER_ROOT}/Fixtures"
