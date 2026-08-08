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

/// An address, canonical network, or inclusive address range used by an admission policy.
///
/// Text parsing preserves the kind expressed by the input: a bare address becomes ``address(_:)``,
/// CIDR notation becomes ``network(_:)``, and strict `lower...upper` text becomes ``range(_:)``.
public enum AdmissionRule: Sendable, Hashable, LosslessStringConvertible {
    /// One IPv4 or IPv6 address, interpreted as exactly one host.
    ///
    /// Programmatic `AnyIPAddress` values may carry prefix-length context. An address rule keeps
    /// only the literal address bits for rendering, equality, hashing, and containment.
    case address(AnyIPAddress)

    /// One canonical IPv4 or IPv6 network.
    case network(AnyIPNetwork)

    /// One inclusive, same-family IPv4 or IPv6 address range.
    case range(AnyIPAddressRange)

    /// Parses a bare address, CIDR network, or strict address range.
    public init?(_ description: String) {
        if description.contains("...") {
            guard let range = AnyIPAddressRange(description) else { return nil }
            self = .range(range)
        } else if description.contains("/") {
            guard let network = AnyIPNetwork(description) else { return nil }
            self = .network(network)
        } else {
            guard let address = AnyIPAddress(description) else { return nil }
            self = .address(address)
        }
    }

    /// The canonical text representation of this rule and its original rule kind.
    public var description: String {
        switch self {
        case .address(let address):
            return address.addressLiteral
        case .network(let network):
            return network.description
        case .range(let range):
            return range.description
        }
    }

    /// Returns whether the supplied address is covered by this rule.
    public func contains(_ address: AnyIPAddress) -> Bool {
        switch (self, address) {
        case (.address(.v4(let ruleAddress)), .v4(let candidate)):
            return ruleAddress.address == candidate.address
        case (.address(.v6(let ruleAddress)), .v6(let candidate)):
            return ruleAddress.address == candidate.address
        case (.address, _):
            return false
        case (.network(let network), _):
            return network.contains(address)
        case (.range(let range), _):
            return range.contains(address)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.address(.v4(let lhs)), .address(.v4(let rhs))):
            // An admission address is one host. Prefix context on a programmatic
            // AnyIPAddress must not change rule identity or membership.
            return lhs.address == rhs.address
        case (.address(.v6(let lhs)), .address(.v6(let rhs))):
            return lhs.address == rhs.address
        case (.network(let lhs), .network(let rhs)):
            return lhs == rhs
        case (.range(let lhs), .range(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .address(.v4(let address)):
            // Hash the same literal bits used by equality, not IPAddress prefix context.
            hasher.combine(0 as UInt8)
            hasher.combine(0 as UInt8)
            hasher.combine(address.address)
        case .address(.v6(let address)):
            hasher.combine(0 as UInt8)
            hasher.combine(1 as UInt8)
            hasher.combine(address.address)
        case .network(let network):
            hasher.combine(1 as UInt8)
            hasher.combine(network)
        case .range(let range):
            hasher.combine(2 as UInt8)
            hasher.combine(range)
        }
    }
}
