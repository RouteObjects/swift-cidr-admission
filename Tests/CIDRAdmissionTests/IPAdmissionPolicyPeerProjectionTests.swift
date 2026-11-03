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
import Testing

@Suite("Detailed Decision Peer Projection Tests")
struct IPAdmissionPolicyPeerProjectionTests {
    @Test("Every legal peer prefix preserves complete decisions across rule kinds and families")
    func exhaustivePrefixContexts() throws {
        let addresses = try rules(["192.0.2.3", "2001:db8::3"])
        let networks = try rules(["192.0.2.0/24", "2001:db8::/120"])
        let ranges = try rules(["192.0.2.2...192.0.2.7", "2001:db8::2...2001:db8::7"])
        let all = try rules(["0.0.0.0/0", "::/0"])
        let extremes = try rules([
            "0.0.0.0/32", "255.255.255.255/32", "::/128",
            "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128", "::ffff:192.0.2.3/128",
        ])
        let combinations: [([AdmissionRule], [AdmissionRule])] = [
            ([], []), (addresses, []), (networks, []), (ranges, []),
            ([], addresses), ([], networks), ([], ranges),
            (addresses + networks + ranges, ranges + addresses),
            (all, ranges + networks + extremes), (extremes, []),
        ]
        let literals: [(String, Int)] = [
            ("0.0.0.0", 32), ("255.255.255.255", 32),
            ("192.0.2.1", 32), ("192.0.2.2", 32), ("192.0.2.3", 32),
            ("192.0.2.7", 32), ("192.0.2.8", 32), ("192.0.2.255", 32), ("192.0.3.0", 32),
            ("::", 128), ("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", 128),
            ("2001:db8::1", 128), ("2001:db8::2", 128), ("2001:db8::3", 128),
            ("2001:db8::7", 128), ("2001:db8::8", 128), ("2001:db8::ff", 128),
            ("2001:db8::100", 128), ("::ffff:192.0.2.3", 128),
        ]
        let peers = try literals.flatMap { literal, width in
            try (0...width).map { try #require(AnyIPAddress("\(literal)/\($0)")) }
        }
        for defaultAction in [AdmissionAction.allow, .deny] {
            for (allow, deny) in combinations {
                let policy = IPAdmissionPolicy(allowRules: allow, denyRules: deny, defaultAction: defaultAction)
                for peer in peers {
                    assertAgreement(policy, peer)
                }
            }
        }
    }

    @Test("Overlapping rule permutations retain first source rule and deny precedence")
    func overlappingSourceOrder() throws {
        for (literal, network, range, opposite) in [
            ("192.0.2.3", "192.0.2.0/24", "192.0.2.2...192.0.2.7", "::/0"),
            ("2001:db8::3", "2001:db8::/120", "2001:db8::2...2001:db8::7", "0.0.0.0/0"),
        ] {
            let addressRule = AdmissionRule.address(try #require(AnyIPAddress("\(literal)/0")))
            let candidates = [addressRule] + (try rules([network, range]))
            let peer = try #require(AnyIPAddress("\(literal)/0"))
            let otherFamily = try #require(AdmissionRule(opposite))
            for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
                let ordered = [otherFamily] + order.map { candidates[$0] }
                let allow = IPAdmissionPolicy(allowRules: ordered, denyRules: [])
                let deny = IPAdmissionPolicy(allowRules: candidates, denyRules: ordered, defaultAction: .allow)
                #expect(allow.decision(for: peer) == .allow(reason: .matched(ruleSet: .allow, rule: ordered[1])))
                #expect(deny.decision(for: peer) == .deny(reason: .matched(ruleSet: .deny, rule: ordered[1])))
                assertAgreement(allow, peer)
                assertAgreement(deny, peer)
            }
        }
    }

    @Test("Equal address rules retain their original stored prefix context in reasons")
    func duplicateSourceRepresentation() throws {
        for literal in ["192.0.2.3", "2001:db8::3"] {
            let contextual = AdmissionRule.address(try #require(AnyIPAddress("\(literal)/0")))
            let host = AdmissionRule.address(try #require(AnyIPAddress(literal)))
            #expect(contextual == host)
            for ordered in [[contextual, host], [host, contextual]] {
                for defaultAction in [AdmissionAction.allow, .deny] {
                    let peer = try #require(AnyIPAddress("\(literal)/1"))
                    assertAgreement(IPAdmissionPolicy(allowRules: ordered, denyRules: [], defaultAction: defaultAction), peer)
                    assertAgreement(IPAdmissionPolicy(allowRules: ordered, denyRules: ordered, defaultAction: defaultAction), peer)
                }
            }
        }
    }

    @Test("Seeded mixed source policies agree with the unchanged per-rule reference")
    func seededMixedPolicies() throws {
        var pool = try rules([
            "192.0.2.0/25", "192.0.2.128/25", "192.0.2.3", "192.0.2.255",
            "192.0.2.2...192.0.2.7", "192.0.2.250...192.0.3.4",
            "2001:db8::/121", "2001:db8::80/121", "2001:db8::3", "2001:db8::ff",
            "2001:db8::2...2001:db8::7", "2001:db8::fa...2001:db8::104",
            "::ffff:192.0.2.3/128",
        ])
        pool += [
            .address(try #require(AnyIPAddress("192.0.2.3/0"))),
            .address(try #require(AnyIPAddress("2001:db8::3/0"))),
        ]
        var random = ProjectionRandom()
        for _ in 0..<32 {
            let allow = (0..<Int(random.next() % 33)).map { _ in pool[Int(random.next() % UInt64(pool.count))] }
            let deny = (0..<Int(random.next() % 25)).map { _ in pool[Int(random.next() % UInt64(pool.count))] }
            for defaultAction in [AdmissionAction.allow, .deny] {
                let policy = IPAdmissionPolicy(allowRules: allow, denyRules: deny, defaultAction: defaultAction)
                for _ in 0..<128 {
                    let value = random.next() % 512
                    let text: String
                    if random.next().isMultiple(of: 2) {
                        text = "192.0.\(2 + value / 256).\(value % 256)/\(random.next() % 33)"
                    } else {
                        text = "2001:db8::\(String(value, radix: 16))/\(random.next() % 129)"
                    }
                    assertAgreement(policy, try #require(AnyIPAddress(text)))
                }
            }
        }
    }

    @Test("Delayed network projection survives misses and the deny-to-allow transition")
    func delayedProjection() throws {
        for (literal, misses, network, opposite) in [
            ("192.0.2.3", ["192.0.2.1", "192.0.2.8...192.0.2.10", "198.51.100.0/24"], "192.0.2.0/24", "::/0"),
            ("2001:db8::3", ["2001:db8::1", "2001:db8::8...2001:db8::a", "2001:db8:1::/48"], "2001:db8::/120", "0.0.0.0/0"),
        ] {
            let peer = try #require(AnyIPAddress("\(literal)/0"))
            let preceding = try rules([opposite] + misses)
            let match = try #require(AdmissionRule(network))
            for deny in [Array(preceding.dropLast()), preceding] {
                let policy = IPAdmissionPolicy(allowRules: preceding + [match], denyRules: deny)
                #expect(policy.decision(for: peer) == .allow(reason: .matched(ruleSet: .allow, rule: match)))
                assertAgreement(policy, peer)
            }
        }
    }

    @Test("Peer projection remains local to repeated and concurrent decisions")
    func independentDecisions() async throws {
        let policy = IPAdmissionPolicy(
            allowRules: try rules(["192.0.2.0/24", "2001:db8::/120"]),
            denyRules: try rules(["192.0.2.1", "2001:db8::1", "192.0.2.4...192.0.2.7", "2001:db8::4...2001:db8::7", "198.51.100.0/24", "2001:db8:1::/48"])
        )
        let peers = try [
            "192.0.2.1/0", "2001:db8::1/1", "192.0.2.3/0", "2001:db8::3/0",
            "192.0.2.4/24", "2001:db8::7/120", "198.51.100.1/0", "2001:db8:1::1/0",
            "203.0.113.1/32", "2001:db8:2::1/128",
        ].map { try #require(AnyIPAddress($0)) }
        // Reuse one immutable policy; each decision must own its lazy peer state.
        await withTaskGroup(of: Void.self) { group in
            for offset in peers.indices {
                group.addTask {
                    for iteration in 0..<100 {
                        assertAgreement(policy, peers[(offset + iteration) % peers.count])
                    }
                }
            }
        }
    }

    @Test("Every phase-transition position retains the triggering rule and suffix order")
    func phaseTransitionPositions() throws {
        for (literal, missAddress, missRange, missNetwork, hitNetwork, hitRange, opposite) in [
            ("192.0.2.3", "192.0.2.1", "192.0.2.8...192.0.2.10", "198.51.100.0/24", "192.0.2.0/24", "192.0.2.2...192.0.2.7", "::/0"),
            ("2001:db8::3", "2001:db8::1", "2001:db8::8...2001:db8::a", "2001:db8:1::/48", "2001:db8::/120", "2001:db8::2...2001:db8::7", "0.0.0.0/0"),
        ] {
            let peer = try #require(AnyIPAddress("\(literal)/0"))
            let hostRule = AdmissionRule.address(peer)
            let misses = try rules([missAddress, opposite, missRange, opposite, missAddress])
            let matchingNetwork = try #require(AdmissionRule(hitNetwork))
            let missingNetwork = try #require(AdmissionRule(missNetwork))
            let matchingRange = try #require(AdmissionRule(hitRange))
            for position in 0...misses.count {
                for defaultAction in [AdmissionAction.allow, .deny] {
                    for tail in [
                        [matchingNetwork, hostRule, matchingRange],
                        [missingNetwork, hostRule, matchingNetwork],
                        [missingNetwork, matchingRange, matchingNetwork],
                        [hostRule, matchingNetwork],
                        [missingNetwork],
                    ] {
                        // Exercise phase entry at either end or in the middle, including no suffix match.
                        let ordered = Array(misses.prefix(position)) + tail + Array(misses.dropFirst(position))
                        assertAgreement(IPAdmissionPolicy(allowRules: ordered, denyRules: misses, defaultAction: defaultAction), peer)
                        assertAgreement(IPAdmissionPolicy(allowRules: [matchingNetwork], denyRules: ordered, defaultAction: defaultAction), peer)
                        assertAgreement(IPAdmissionPolicy(allowRules: ordered, denyRules: [missingNetwork], defaultAction: defaultAction), peer)
                    }
                }
            }
        }
    }

    private func rules(_ text: [String]) throws -> [AdmissionRule] {
        try text.map { try #require(AdmissionRule($0)) }
    }

    private func assertAgreement(_ policy: IPAdmissionPolicy, _ peer: AnyIPAddress) {
        // Preserve the old public-rule scan as an oracle, including complete source-rule reasons.
        let expected: AdmissionDecision
        if let rule = policy.deny.first(where: { $0.contains(peer) }) {
            expected = .deny(reason: .matched(ruleSet: .deny, rule: rule))
        } else if let rule = policy.allow.first(where: { $0.contains(peer) }) {
            expected = .allow(reason: .matched(ruleSet: .allow, rule: rule))
        } else {
            expected = policy.defaultAction == .allow ? .allow(reason: .defaultAction) : .deny(reason: .defaultAction)
        }
        let actual = policy.decision(for: peer)
        #expect(actual == expected)
        #expect(actual.isAllowed == policy.allows(peer))
        if case .matched(_, let actualRule) = actual.reason,
           case .matched(_, let expectedRule) = expected.reason {
            // Address-rule equality intentionally ignores context, so inspect stored context separately.
            switch (actualRule, expectedRule) {
            case (.address(.v4(let actual)), .address(.v4(let expected))):
                #expect(actual.prefixLength == expected.prefixLength)
            case (.address(.v6(let actual)), .address(.v6(let expected))):
                #expect(actual.prefixLength == expected.prefixLength)
            default:
                break
            }
        }
    }
}

private struct ProjectionRandom {
    private var state: UInt64 = 0x5052_4F4A_4543_544E

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
