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

@Suite("IP Admission Policy Randomized Agreement Tests")
struct IPAdmissionPolicyRandomizedAgreementTests {
    @Test("Seeded indexed lookups agree with detailed decisions")
    func seededIndexedAndDetailedAgreement() throws {
        let allowRules = try makeAllowRules(count: 200)
        let denyRules = try makeDenyRules(count: 200)
        let policy = IPAdmissionPolicy(
            allowRules: allowRules,
            denyRules: denyRules,
            defaultAction: .deny
        )
        var random = SplitMix64(seed: 0x4144_4D49_5353_494F)

        for _ in 0..<20_000 {
            let address: AnyIPAddress
            switch random.next() & 3 {
            case 0:
                let slot = Int(random.next() % 400)
                address = try #require(
                    AnyIPAddress("10.\(slot / 256).\(slot % 256).\(random.next() & 0x1F)")
                )
            case 1:
                let slot = Int(random.next() % 400)
                address = try #require(
                    AnyIPAddress(
                        "172.\(16 + slot / 256).\(slot % 256).\(random.next() & 0x1F)"
                    )
                )
            case 2:
                let slot = random.next() % 400
                address = try #require(
                    AnyIPAddress(
                        "2001:db8:\(String(slot, radix: 16))::\(String(random.next() & 0x1F, radix: 16))"
                    )
                )
            default:
                let slot = random.next() % 400
                address = try #require(
                    AnyIPAddress(
                        "2001:db8:\(String(0x8000 + slot, radix: 16))::\(String(random.next() & 0x1F, radix: 16))"
                    )
                )
            }

            #expect(policy.allows(address) == policy.decision(for: address).isAllowed)
        }
    }

    private func makeAllowRules(count: Int) throws -> [AdmissionRule] {
        var rules: [AdmissionRule] = []
        rules.reserveCapacity(count * 2)
        for index in 0..<count {
            let slot = index * 2
            let ipv4Stem = "10.\(slot / 256).\(slot % 256)"
            let ipv6Stem = "2001:db8:\(String(slot, radix: 16))"
            rules.append(try #require(rule(stem: ipv4Stem, kind: index % 3, isIPv6: false)))
            rules.append(try #require(rule(stem: ipv6Stem, kind: index % 3, isIPv6: true)))
        }
        return rules
    }

    private func makeDenyRules(count: Int) throws -> [AdmissionRule] {
        var rules: [AdmissionRule] = []
        rules.reserveCapacity(count * 2)
        for index in 0..<count {
            let slot = index * 2
            let overlapsAllow = index.isMultiple(of: 4)
            let ipv4Stem =
                overlapsAllow
                ? "10.\(slot / 256).\(slot % 256)"
                : "172.\(16 + slot / 256).\(slot % 256)"
            let ipv6Subnet = overlapsAllow ? slot : 0x8000 + slot
            let ipv6Stem = "2001:db8:\(String(ipv6Subnet, radix: 16))"
            let kind = overlapsAllow ? (index + 2) % 3 : (index + 1) % 3
            rules.append(
                try #require(
                    rule(
                        stem: ipv4Stem,
                        kind: kind,
                        isIPv6: false,
                        overlappingAddress: overlapsAllow
                    )
                )
            )
            rules.append(
                try #require(
                    rule(
                        stem: ipv6Stem,
                        kind: kind,
                        isIPv6: true,
                        overlappingAddress: overlapsAllow
                    )
                )
            )
        }
        return rules
    }

    private func rule(
        stem: String,
        kind: Int,
        isIPv6: Bool,
        overlappingAddress: Bool = false
    ) -> AdmissionRule? {
        let separator = isIPv6 ? "::" : "."
        switch kind {
        case 0:
            return AdmissionRule("\(stem)\(separator)\(overlappingAddress ? "5" : "1")")
        case 1:
            let lower = overlappingAddress ? "16" : "4"
            let upper = overlappingAddress ? "23" : "7"
            return AdmissionRule("\(stem)\(separator)\(lower)...\(stem)\(separator)\(upper)")
        default:
            let suffix: String
            if isIPv6 {
                suffix = overlappingAddress ? "0/124" : "10/124"
            } else {
                suffix = overlappingAddress ? "0/28" : "16/28"
            }
            return AdmissionRule("\(stem)\(separator)\(suffix)")
        }
    }
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
