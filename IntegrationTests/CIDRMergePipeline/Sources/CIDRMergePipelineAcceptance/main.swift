//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
//
// Copyright (c) 2026 Craig A. Munro
//
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CIDR
import CIDRAdmission
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private enum AcceptanceError: Error, CustomStringConvertible {
    case failed(String)
    case usage

    var description: String {
        switch self {
        case .failed(let message): message
        case .usage:
            "usage: CIDRMergePipelineAcceptance verify ALLOW_RANGES DENY_RANGES ALLOW_CIDR DENY_CIDR EMPTY MIXED | expect-failure KIND ROLE ALLOW|- DENY|- [DETAIL ...]"
        }
    }
}

private enum ExpectedReason {
    case defaultAction
    case matched(AdmissionRuleSet)
}

private struct Probe {
    let text: String
    let action: AdmissionAction
    let reason: ExpectedReason
    let rangeRule: String?
    let cidrRule: String?

    init(
        text: String,
        action: AdmissionAction,
        reason: ExpectedReason,
        rangeRule: String? = nil,
        cidrRule: String? = nil
    ) {
        self.text = text
        self.action = action
        self.reason = reason
        self.rangeRule = rangeRule
        self.cidrRule = cidrRule
    }
}

private enum ArtifactRepresentation {
    case ranges
    case cidr
}

private struct PolicyCase {
    let name: String
    let allowRepresentation: ArtifactRepresentation
    let denyRepresentation: ArtifactRepresentation
    let policy: IPAdmissionPolicy
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@main
private struct CIDRMergePipelineAcceptance {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = "CIDRMergePipelineAcceptance: error: \(error)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            throw AcceptanceError.usage
        }

        switch command {
        case "verify":
            guard arguments.count == 7 else { throw AcceptanceError.usage }
            try verify(
                allowRanges: fileURL(arguments[1]),
                denyRanges: fileURL(arguments[2]),
                allowCIDR: fileURL(arguments[3]),
                denyCIDR: fileURL(arguments[4]),
                empty: fileURL(arguments[5]),
                mixed: fileURL(arguments[6])
            )
        case "expect-failure":
            guard arguments.count >= 5,
                let ruleSet = AdmissionRuleSet(rawValue: arguments[2])
            else {
                throw AcceptanceError.usage
            }
            try expectFailure(
                kind: arguments[1],
                ruleSet: ruleSet,
                allow: optionalFileURL(arguments[3]),
                deny: optionalFileURL(arguments[4]),
                details: Array(arguments.dropFirst(5))
            )
        default:
            throw AcceptanceError.usage
        }
    }

    private static func verify(
        allowRanges: URL,
        denyRanges: URL,
        allowCIDR: URL,
        denyCIDR: URL,
        empty: URL,
        mixed: URL
    ) throws {
        let policies: [PolicyCase] = try [
            PolicyCase(
                name: "ranges/ranges",
                allowRepresentation: .ranges,
                denyRepresentation: .ranges,
                policy: load(allow: allowRanges, deny: denyRanges)
            ),
            PolicyCase(
                name: "cidr/cidr",
                allowRepresentation: .cidr,
                denyRepresentation: .cidr,
                policy: load(allow: allowCIDR, deny: denyCIDR)
            ),
            PolicyCase(
                name: "ranges/cidr",
                allowRepresentation: .ranges,
                denyRepresentation: .cidr,
                policy: load(allow: allowRanges, deny: denyCIDR)
            ),
            PolicyCase(
                name: "cidr/ranges",
                allowRepresentation: .cidr,
                denyRepresentation: .ranges,
                policy: load(allow: allowCIDR, deny: denyRanges)
            ),
        ]

        try require(policies[0].policy.allow.count == 6, "range allow cardinality changed")
        try require(policies[0].policy.deny.count == 6, "range deny cardinality changed")
        try require(policies[1].policy.allow.count == 10, "CIDR allow cardinality changed")
        try require(policies[1].policy.deny.count == 10, "CIDR deny cardinality changed")
        try require(
            policies[0].policy.allow.allSatisfy(isRangeRule)
                && policies[0].policy.deny.allSatisfy(isRangeRule),
            "range artifacts did not remain range source rules"
        )
        try require(
            policies[1].policy.allow.allSatisfy(isNetworkRule)
                && policies[1].policy.deny.allSatisfy(isNetworkRule),
            "CIDR artifacts did not remain network source rules"
        )

        let probes = [
            Probe(text: "192.0.2.0", action: .deny, reason: .defaultAction),
            Probe(
                text: "192.0.2.1",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "192.0.2.1...192.0.2.7",
                cidrRule: "192.0.2.1/32"
            ),
            Probe(text: "192.0.2.2", action: .allow, reason: .matched(.allow)),
            Probe(
                text: "192.0.2.3",
                action: .deny,
                reason: .matched(.deny),
                rangeRule: "192.0.2.3...192.0.2.6",
                cidrRule: "192.0.2.3/32"
            ),
            Probe(text: "192.0.2.6", action: .deny, reason: .matched(.deny)),
            Probe(text: "192.0.2.7", action: .allow, reason: .matched(.allow)),
            Probe(text: "192.0.2.8", action: .deny, reason: .defaultAction),
            Probe(
                text: "192.0.2.250",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "192.0.2.250...192.0.2.250",
                cidrRule: "192.0.2.250/32"
            ),
            Probe(text: "198.51.100.127", action: .deny, reason: .defaultAction),
            Probe(
                text: "198.51.100.128",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "198.51.100.128...198.51.100.191",
                cidrRule: "198.51.100.128/26"
            ),
            Probe(text: "198.51.100.191", action: .allow, reason: .matched(.allow)),
            Probe(text: "198.51.100.192", action: .deny, reason: .defaultAction),
            Probe(
                text: "203.0.113.64",
                action: .deny,
                reason: .matched(.deny),
                rangeRule: "203.0.113.64...203.0.113.67",
                cidrRule: "203.0.113.64/30"
            ),
            Probe(text: "203.0.113.67", action: .deny, reason: .matched(.deny)),
            Probe(text: "203.0.113.68", action: .deny, reason: .defaultAction),
            Probe(
                text: "203.0.113.250",
                action: .deny,
                reason: .matched(.deny),
                rangeRule: "203.0.113.250...203.0.113.250",
                cidrRule: "203.0.113.250/32"
            ),
            Probe(text: "2001:db8::", action: .deny, reason: .defaultAction),
            Probe(
                text: "2001:db8::1",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "2001:db8::1...2001:db8::7",
                cidrRule: "2001:db8::1/128"
            ),
            Probe(text: "2001:db8::2", action: .allow, reason: .matched(.allow)),
            Probe(
                text: "2001:db8::3",
                action: .deny,
                reason: .matched(.deny),
                rangeRule: "2001:db8::3...2001:db8::6",
                cidrRule: "2001:db8::3/128"
            ),
            Probe(text: "2001:db8::6", action: .deny, reason: .matched(.deny)),
            Probe(text: "2001:db8::7", action: .allow, reason: .matched(.allow)),
            Probe(text: "2001:db8::8", action: .deny, reason: .defaultAction),
            Probe(
                text: "2001:db8:1::",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "2001:db8:1::...2001:db8:1::3",
                cidrRule: "2001:db8:1::/126"
            ),
            Probe(text: "2001:db8:1::3", action: .allow, reason: .matched(.allow)),
            Probe(text: "2001:db8:1::4", action: .deny, reason: .defaultAction),
            Probe(
                text: "2001:db8:abcd::42",
                action: .allow,
                reason: .matched(.allow),
                rangeRule: "2001:db8:abcd::42...2001:db8:abcd::42",
                cidrRule: "2001:db8:abcd::42/128"
            ),
            Probe(
                text: "2001:db8:eeee::42",
                action: .deny,
                reason: .matched(.deny),
                rangeRule: "2001:db8:eeee::42...2001:db8:eeee::42",
                cidrRule: "2001:db8:eeee::42/128"
            ),
            Probe(text: "2001:db8:ffff::", action: .deny, reason: .matched(.deny)),
            Probe(text: "2001:db8:ffff::1", action: .deny, reason: .matched(.deny)),
            Probe(text: "2001:db8:ffff::2", action: .deny, reason: .defaultAction),
        ]

        for probe in probes {
            guard let address = AnyIPAddress(probe.text) else {
                throw AcceptanceError.failed("invalid fixed probe \(probe.text)")
            }
            try verify(address: address, expected: probe, policies: policies)
        }

        var randomizedAddresses: [AnyIPAddress] = []
        randomizedAddresses.reserveCapacity(24_608)
        for base: UInt32 in [0xC000_0200, 0xC633_6400, 0xCB00_7100] {
            for offset in 0..<256 {
                randomizedAddresses.append(AnyIPAddress(IPv4Address(address: base + UInt32(offset))))
            }
        }
        let ipv6DocumentationBase = UInt128(0x2001_0DB8) << 96
        for subnet: UInt128 in [0, 1, 0xFFFF] {
            let base = ipv6DocumentationBase | (subnet << 80)
            for offset in 0..<512 {
                randomizedAddresses.append(AnyIPAddress(IPv6Address(address: base + UInt128(offset))))
            }
        }

        var random = SplitMix64(seed: 0x4349_4452_4D45_5247)
        for _ in 0..<10_000 {
            randomizedAddresses.append(
                AnyIPAddress(IPv4Address(address: UInt32(truncatingIfNeeded: random.next())))
            )
            let high = UInt128(random.next()) << 64
            let low = UInt128(random.next())
            randomizedAddresses.append(AnyIPAddress(IPv6Address(address: high | low)))
        }

        for address in randomizedAddresses {
            let reference = policies[0].policy.decision(for: address)
            for policyCase in policies {
                let decision = policyCase.policy.decision(for: address)
                try require(
                    policyCase.policy.allows(address) == decision.isAllowed,
                    "indexed and detailed decisions disagree for \(address) in \(policyCase.name)"
                )
                try require(
                    decision.action == reference.action,
                    "representations disagree for \(address) in \(policyCase.name)"
                )
                try require(
                    ruleSet(for: decision.reason) == ruleSet(for: reference.reason),
                    "diagnostic rule sets disagree for \(address) in \(policyCase.name)"
                )
            }
        }

        try verifyRolePresence(empty: empty, allow: allowRanges, deny: denyRanges)
        try verifyMixedKinds(mixed)

        print(
            "pipeline acceptance: 4 representation pairs, \(probes.count) boundaries, "
                + "\(randomizedAddresses.count) deterministic agreement probes"
        )
    }

    private static func verify(
        address: AnyIPAddress,
        expected: Probe,
        policies: [PolicyCase]
    ) throws {
        for policyCase in policies {
            let decision = policyCase.policy.decision(for: address)
            try require(
                decision.action == expected.action,
                "unexpected action for \(address) in \(policyCase.name)"
            )
            try require(
                policyCase.policy.allows(address) == decision.isAllowed,
                "indexed and detailed decisions disagree for \(address) in \(policyCase.name)"
            )

            switch (expected.reason, decision.reason) {
            case (.defaultAction, .defaultAction):
                break
            case (.matched(let expectedRuleSet), .matched(let actualRuleSet, let actualRule)):
                try require(
                    expectedRuleSet == actualRuleSet,
                    "unexpected diagnostic role for \(address) in \(policyCase.name)"
                )
                let representation =
                    expectedRuleSet == .allow
                    ? policyCase.allowRepresentation : policyCase.denyRepresentation
                let expectedRule =
                    representation == .ranges ? expected.rangeRule : expected.cidrRule
                if let expectedRule {
                    try require(
                        actualRule.description == expectedRule,
                        "unexpected source rule for \(address) in \(policyCase.name): "
                            + "expected \(expectedRule), found \(actualRule)"
                    )
                }
            default:
                throw AcceptanceError.failed(
                    "unexpected diagnostic reason for \(address) in \(policyCase.name)"
                )
            }
        }
    }

    private static func verifyRolePresence(empty: URL, allow: URL, deny: URL) throws {
        let emptyDefaultDeny = try load(allow: nil, deny: nil)
        let emptyDefaultAllow = try load(allow: nil, deny: nil, defaultAction: .allow)
        let explicitEmptyAllow = try load(allow: empty, deny: nil)
        let explicitEmptyDeny = try load(allow: nil, deny: empty, defaultAction: .allow)
        let allowOnly = try load(allow: allow, deny: nil)
        let denyOnly = try load(allow: nil, deny: deny, defaultAction: .allow)
        guard let miss = AnyIPAddress("198.18.0.1"),
            let allowed = AnyIPAddress("192.0.2.1"),
            let denied = AnyIPAddress("203.0.113.64")
        else {
            throw AcceptanceError.failed("invalid role-presence probe")
        }

        try require(!emptyDefaultDeny.allows(miss), "omitted roles ignored default deny")
        try require(emptyDefaultAllow.allows(miss), "omitted roles ignored default allow")
        try require(!explicitEmptyAllow.allows(miss), "explicit empty allow was not empty")
        try require(explicitEmptyDeny.allows(miss), "explicit empty deny was not empty")
        try require(allowOnly.allows(allowed), "allow-only policy did not allow its coverage")
        try require(!allowOnly.allows(miss), "allow-only policy ignored default deny")
        try require(!denyOnly.allows(denied), "deny-only policy did not deny its coverage")
        try require(denyOnly.allows(miss), "deny-only policy ignored default allow")
    }

    private static func verifyMixedKinds(_ mixed: URL) throws {
        let policy = try load(allow: mixed, deny: nil)
        try require(policy.allow.count == 3, "mixed-kind fixture cardinality changed")
        guard case .address = policy.allow[0],
            case .network = policy.allow[1],
            case .range = policy.allow[2]
        else {
            throw AcceptanceError.failed("mixed-kind source representation was not preserved")
        }

        let probes = [
            ("192.0.2.250", 0),
            ("198.51.100.1", 1),
            ("2001:db8:2::2", 2),
        ]
        for (text, ruleIndex) in probes {
            guard let address = AnyIPAddress(text) else {
                throw AcceptanceError.failed("invalid mixed-kind probe \(text)")
            }
            let decision = policy.decision(for: address)
            try require(policy.allows(address), "mixed-kind rule did not cover \(text)")
            guard case .matched(.allow, let actualRule) = decision.reason else {
                throw AcceptanceError.failed("mixed-kind decision did not retain allow source rule")
            }
            try require(
                actualRule == policy.allow[ruleIndex],
                "mixed-kind decision returned the wrong source rule for \(text)"
            )
        }
    }

    private static func expectFailure(
        kind: String,
        ruleSet: AdmissionRuleSet,
        allow: URL?,
        deny: URL?,
        details: [String]
    ) throws {
        var policy: IPAdmissionPolicy?
        do {
            policy = try load(allow: allow, deny: deny)
            throw AcceptanceError.failed("expected \(kind) for \(ruleSet) rules")
        } catch let error as IPAdmissionPolicyFileLoadError {
            try require(policy == nil, "a failed two-role load exposed a partial policy")
            try require(
                matches(
                    error: error,
                    kind: kind,
                    ruleSet: ruleSet,
                    allow: allow,
                    deny: deny,
                    details: details
                ),
                "unexpected typed failure: \(error)"
            )
            print("expected failure: \(kind) (\(ruleSet))")
        }
    }

    private static func matches(
        error: IPAdmissionPolicyFileLoadError,
        kind: String,
        ruleSet: AdmissionRuleSet,
        allow: URL?,
        deny: URL?,
        details: [String]
    ) -> Bool {
        guard let source = ruleSet == .allow ? allow : deny else { return false }
        let path = source.path
        let checksumPath = path + ".sha256"

        return switch (kind, error) {
        case ("file-not-found", .fileNotFound(let actualRuleSet, let actualPath)):
            details.isEmpty && actualRuleSet == ruleSet && actualPath == path
        case ("not-regular", .notRegularFile(let actualRuleSet, let actualPath)):
            details.isEmpty && actualRuleSet == ruleSet && actualPath == path
        case (
            "checksum-not-found",
            .checksumNotFound(let actualRuleSet, let actualPath, let actualChecksumPath)
        ):
            details.isEmpty && actualRuleSet == ruleSet && actualPath == path
                && actualChecksumPath == checksumPath
        case (
            "checksum-malformed",
            .checksumMalformed(let actualRuleSet, let actualPath, let actualChecksumPath)
        ):
            details.isEmpty && actualRuleSet == ruleSet && actualPath == path
                && actualChecksumPath == checksumPath
        case (
            "checksum-filename-mismatch",
            .checksumFilenameMismatch(
                let actualRuleSet,
                let actualPath,
                let actualChecksumPath,
                let expectedFilename,
                let actualFilename
            )
        ):
            details.count == 1 && actualRuleSet == ruleSet && actualPath == path
                && actualChecksumPath == checksumPath
                && expectedFilename == source.lastPathComponent && actualFilename == details[0]
        case (
            "checksum-digest-mismatch",
            .checksumDigestMismatch(
                let actualRuleSet,
                let actualPath,
                let actualChecksumPath,
                let expectedDigest,
                let actualDigest
            )
        ):
            details.count == 2 && actualRuleSet == ruleSet && actualPath == path
                && actualChecksumPath == checksumPath && expectedDigest == details[0]
                && actualDigest == details[1]
        case (
            "invalid-rule",
            .invalidRule(
                let actualRuleSet,
                let actualPath,
                let line,
                let token,
                let reason
            )
        ):
            details.isEmpty && actualRuleSet == ruleSet && actualPath == path && line == 1
                && token == "{" && reason == .malformedValue
        default:
            false
        }
    }

    private static func load(
        allow: URL?,
        deny: URL?,
        defaultAction: AdmissionAction = .deny
    ) throws -> IPAdmissionPolicy {
        try IPAdmissionPolicy(
            fileConfiguration: IPAdmissionPolicyFileConfiguration(
                checksumPolicy: .required,
                defaultAction: defaultAction,
                allowFile: allow,
                denyFile: deny
            )
        )
    }

    private static func ruleSet(for reason: AdmissionDecisionReason) -> AdmissionRuleSet? {
        switch reason {
        case .defaultAction: nil
        case .matched(let ruleSet, _): ruleSet
        }
    }

    private static func isRangeRule(_ rule: AdmissionRule) -> Bool {
        if case .range = rule { return true }
        return false
    }

    private static func isNetworkRule(_ rule: AdmissionRule) -> Bool {
        if case .network = rule { return true }
        return false
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private static func optionalFileURL(_ path: String) -> URL? {
        path == "-" ? nil : fileURL(path)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw AcceptanceError.failed(message) }
    }
}
