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

/// A family-partitioned exact-coverage index for admission membership checks.
struct IPAdmissionCoverageIndex: Sendable, Hashable {
    private let ipv4: IPAddressCoverage<V4>
    private let ipv6: IPAddressCoverage<V6>

    /// Builds normalized IPv4 and IPv6 coverage from every supported admission rule kind.
    init(rules: [AdmissionRule]) {
        var ipv4Ranges: [IPAddressRange<V4>] = []
        var ipv6Ranges: [IPAddressRange<V6>] = []
        let ipv4Count = rules.reduce(into: 0) { count, rule in
            switch rule {
            case .address(.v4), .network(.v4), .range(.v4):
                count += 1
            default:
                break
            }
        }
        // Reserve each family independently so a one-family policy does not allocate a second
        // full-size range buffer for the absent family.
        ipv4Ranges.reserveCapacity(ipv4Count)
        ipv6Ranges.reserveCapacity(rules.count - ipv4Count)

        for rule in rules {
            switch rule {
            case .address(.v4(let address)):
                ipv4Ranges.append(IPAddressRange(address))
            case .address(.v6(let address)):
                ipv6Ranges.append(IPAddressRange(address))
            case .network(.v4(let network)):
                ipv4Ranges.append(IPAddressRange(covering: network))
            case .network(.v6(let network)):
                ipv6Ranges.append(IPAddressRange(covering: network))
            case .range(.v4(let range)):
                ipv4Ranges.append(range)
            case .range(.v6(let range)):
                ipv6Ranges.append(range)
            }
        }

        self.ipv4 = IPAddressCoverage(ipv4Ranges)
        self.ipv6 = IPAddressCoverage(ipv6Ranges)
    }

    /// Returns whether either family-specific coverage index contains the address.
    func contains(_ address: AnyIPAddress) -> Bool {
        switch address {
        case .v4(let address):
            return ipv4.contains(address)
        case .v6(let address):
            return ipv6.contains(address)
        }
    }
}
