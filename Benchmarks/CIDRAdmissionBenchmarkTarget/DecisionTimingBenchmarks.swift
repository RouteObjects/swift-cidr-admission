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

// CHANGE: Network-only controls localize scan costs without changing the public evaluator.
func registerDecisionTimingBenchmarks(
    family: String,
    policy: IPAdmissionPolicy,
    address: AnyIPAddress,
    validationAddresses: [AnyIPAddress],
    metrics: [BenchmarkMetric]
) {
    precondition((policy.allow + policy.deny).allSatisfy {
        if case .network = $0 { return true }
        return false
    })
    for candidate in validationAddresses {
        for peer in [candidate, withZeroPrefix(candidate)] {
            let expected = policy.decision(for: peer)
            precondition(projectOnceDecision(policy, peer) == expected)
            precondition(addressBitsDecision(policy, peer) == expected)
            precondition(erasedHostDecision(policy, peer) == expected)
        }
    }

    let configuration = Benchmark.Configuration(
        metrics: metrics,
        warmupIterations: 30,
        scalingFactor: .one,
        maxDuration: .seconds(10)
    )
    // CHANGE: The production evaluator now normalizes once at entry, not once per rule.
    Benchmark("diagnostic.decision.\(family).production.10000", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(policy.decision(for: address).isAllowed)
        }
    }
    Benchmark("diagnostic.decision.\(family).projectOnce.10000", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(projectOnceDecision(policy, address).isAllowed)
        }
    }
    Benchmark("diagnostic.decision.\(family).addressBits.10000", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(addressBitsDecision(policy, address).isAllowed)
        }
    }
    Benchmark("diagnostic.decision.\(family).erasedHost.10000", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(erasedHostDecision(policy, address).isAllowed)
        }
    }
}

@inline(never)
private func projectOnceDecision(_ policy: IPAdmissionPolicy, _ address: AnyIPAddress) -> AdmissionDecision {
    let host: AnyIPAddress
    switch address {
    case .v4(let peer): host = .v4(IPv4Address(address: peer.address))
    case .v6(let peer): host = .v6(IPv6Address(address: peer.address))
    }
    return scanNetworks(policy, host) { rule, peer in
        switch (rule, peer) {
        case (.network(.v4(let network)), .v4(let candidate)):
            return network.contains(address: candidate)
        case (.network(.v6(let network)), .v6(let candidate)):
            return network.contains(address: candidate)
        default:
            return false
        }
    }
}

@inline(never)
private func addressBitsDecision(_ policy: IPAdmissionPolicy, _ address: AnyIPAddress) -> AdmissionDecision {
    scanNetworks(policy, address) { rule, peer in
        switch (rule, peer) {
        case (.network(.v4(let network)), .v4(let candidate)):
            return (candidate.address & network.mask) == network.prefix
        case (.network(.v6(let network)), .v6(let candidate)):
            return (candidate.address & network.mask) == network.prefix
        default:
            return false
        }
    }
}

// CHANGE: Compare the concrete generic calls with dispatch through CIDR's family-erased API.
@inline(never)
private func erasedHostDecision(_ policy: IPAdmissionPolicy, _ address: AnyIPAddress) -> AdmissionDecision {
    let host: AnyIPAddress
    switch address {
    case .v4(let peer): host = .v4(IPv4Address(address: peer.address))
    case .v6(let peer): host = .v6(IPv6Address(address: peer.address))
    }
    return scanNetworks(policy, host) { rule, peer in
        guard case .network(let network) = rule else { return false }
        return network.contains(address: peer)
    }
}

// CHANGE: Inline only the shared control flow; keep a call boundary around each complete decision.
@inline(__always)
private func scanNetworks(
    _ policy: IPAdmissionPolicy,
    _ address: AnyIPAddress,
    matches: (AdmissionRule, AnyIPAddress) -> Bool
) -> AdmissionDecision {
    if let rule = policy.deny.first(where: { matches($0, address) }) {
        return .deny(reason: .matched(ruleSet: .deny, rule: rule))
    }
    if let rule = policy.allow.first(where: { matches($0, address) }) {
        return .allow(reason: .matched(ruleSet: .allow, rule: rule))
    }
    return policy.defaultAction == .allow ? .allow(reason: .defaultAction) : .deny(reason: .defaultAction)
}

private func withZeroPrefix(_ address: AnyIPAddress) -> AnyIPAddress {
    switch address {
    case .v4(let peer): .v4(IPv4Address(address: peer.address, prefixLength: .zero))
    case .v6(let peer): .v6(IPv6Address(address: peer.address, prefixLength: .zero))
    }
}
