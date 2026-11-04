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

import Benchmark
import CIDR
import CIDRAdmission

// CHANGE: Cover short-circuit, non-network, and mixed-rule paths as well as the existing long network scan.
func registerPeerProjectionBenchmarks(metrics: [BenchmarkMetric]) {
    func rule(_ text: String) -> AdmissionRule {
        guard let value = AdmissionRule(text) else { preconditionFailure("Invalid benchmark rule: \(text)") }
        return value
    }

    func address(_ text: String) -> AnyIPAddress {
        guard let value = AnyIPAddress(text) else { preconditionFailure("Invalid benchmark address: \(text)") }
        return value
    }

    func register(_ name: String, policy: IPAdmissionPolicy, peer: AnyIPAddress, single: Bool = false) {
        let expected: AdmissionDecision
        if let rule = policy.deny.first(where: { $0.contains(peer) }) {
            expected = .deny(reason: .matched(ruleSet: .deny, rule: rule))
        } else if let rule = policy.allow.first(where: { $0.contains(peer) }) {
            expected = .allow(reason: .matched(ruleSet: .allow, rule: rule))
        } else {
            expected = policy.defaultAction == .allow ? .allow(reason: .defaultAction) : .deny(reason: .defaultAction)
        }
        precondition(policy.decision(for: peer) == expected)
        precondition(policy.allows(peer) == expected.isAllowed)
        Benchmark("projection.\(name)", configuration: .init(
            metrics: metrics, warmupIterations: single ? 3_000 : 3,
            scalingFactor: single ? .one : .kilo, maxDuration: .seconds(2)
        )) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(policy.decision(for: peer))
            }
        }
    }

    for family in ["v4", "v6"] {
        let ipv4 = family == "v4"
        func stem(_ index: Int, deny: Bool = false) -> String {
            if ipv4 {
                return "\(deny ? 172 : 10).\(index / 256).\(index % 256)"
            }
            return "2001:db8:\(String((deny ? 0x8000 : 0) + index, radix: 16))"
        }
        let separator = ipv4 ? "." : "::"
        let prefix = ipv4 ? 24 : 120
        let networks = (0..<10_000).map { rule("\(stem($0))\(separator)0/\(prefix)") }
        let firstPeer = address("\(stem(0))\(separator)3/0")
        let hostRule = AdmissionRule.address(firstPeer)
        let rangeRule = rule("\(stem(0))\(separator)2...\(stem(0))\(separator)7")
        register("\(family).empty.defaultDeny", policy: IPAdmissionPolicy(), peer: firstPeer)
        register("\(family).empty.defaultAllow", policy: IPAdmissionPolicy(defaultAction: .allow), peer: firstPeer)
        register("\(family).network.denyFirst.10000", policy: IPAdmissionPolicy(allowRules: [], denyRules: networks), peer: firstPeer)
        register("\(family).network.allowFirst.10000", policy: IPAdmissionPolicy(allowRules: networks, denyRules: []), peer: firstPeer)
        register("\(family).address.denyFirst.1", policy: IPAdmissionPolicy(allowRules: [networks[0]], denyRules: [hostRule]), peer: firstPeer)
        register("\(family).range.denyFirst.1", policy: IPAdmissionPolicy(allowRules: [networks[0]], denyRules: [rangeRule]), peer: firstPeer)

        func mixedRules(deny: Bool) -> [AdmissionRule] {
            (0..<1_000).map { index in
                let base = stem(index, deny: deny) + separator
                switch index % 3 {
                case 0: return .address(address(base + "3/0"))
                case 1: return rule(base + "0/\(prefix)")
                default: return rule(base + "2..." + base + "7")
                }
            }
        }
        let mixed = IPAdmissionPolicy(allowRules: mixedRules(deny: false), denyRules: mixedRules(deny: true), defaultAction: .allow)
        register("\(family).mixed.denyMissAllowLast.1000", policy: mixed, peer: address("\(stem(999))\(separator)3/0"), single: true)
        register("\(family).mixed.defaultAllowMiss.1000", policy: mixed, peer: address(ipv4 ? "203.0.113.1/0" : "2001:db9::1/0"), single: true)
    }
}
