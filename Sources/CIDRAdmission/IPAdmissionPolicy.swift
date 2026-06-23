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

import Foundation
import CIDR

/// The action produced by an admission policy.
public enum AdmissionAction: String, Sendable, Hashable, Codable, CustomStringConvertible {
    /// Permit the address.
    case allow
    /// Reject the address.
    case deny

    public var description: String { rawValue }
}

/// The rule set that produced a decision.
public enum AdmissionRuleSet: String, Sendable, Hashable, Codable, CustomStringConvertible {
    /// A configured allow rule.
    case allow
    /// A configured deny rule.
    case deny

    public var description: String { rawValue }
}

/// The reason an address was allowed or denied.
public enum AdmissionDecisionReason: Sendable, Hashable {
    /// The address matched a configured allow or deny network.
    case matched(ruleSet: AdmissionRuleSet, network: AnyIPNetwork)
    /// No configured rule matched, so the policy returned its default action.
    case defaultAction
}

/// The result of evaluating an address against an admission policy.
public enum AdmissionDecision: Sendable, Hashable {
    /// The address is allowed.
    case allow(reason: AdmissionDecisionReason)
    /// The address is denied.
    case deny(reason: AdmissionDecisionReason)

    /// The normalized action for this decision.
    public var action: AdmissionAction {
        switch self {
        case .allow:
            return .allow
        case .deny:
            return .deny
        }
    }

    /// A Boolean convenience for admission checks that do not need reason details.
    public var isAllowed: Bool {
        action == .allow
    }

    /// The reason attached to this decision.
    public var reason: AdmissionDecisionReason {
        switch self {
        case .allow(let reason), .deny(let reason):
            return reason
        }
    }
}

/// A JSON-decodable admission policy configuration.
public struct IPAdmissionPolicyConfiguration: Sendable, Hashable, Codable {
    private enum CodingKeys: String, CodingKey {
        case defaultAction
        case allow
        case deny
    }

    /// The action used when an address does not match a configured allow or deny network.
    public var defaultAction: AdmissionAction
    /// CIDR networks that allow matching addresses when no deny rule matches.
    public var allow: [String]
    /// CIDR networks that reject matching addresses.
    public var deny: [String]

    public init(
        defaultAction: AdmissionAction = .deny,
        allow: [String] = [],
        deny: [String] = []
    ) {
        self.defaultAction = defaultAction
        self.allow = allow
        self.deny = deny
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultAction = try container.decodeIfPresent(AdmissionAction.self, forKey: .defaultAction) ?? .deny
        self.allow = try container.decodeIfPresent([String].self, forKey: .allow) ?? []
        self.deny = try container.decodeIfPresent([String].self, forKey: .deny) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultAction, forKey: .defaultAction)
        try container.encode(allow, forKey: .allow)
        try container.encode(deny, forKey: .deny)
    }

    /// Decodes a configuration from JSON data.
    public static func json(
        data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> IPAdmissionPolicyConfiguration {
        try decoder.decode(Self.self, from: data)
    }

    /// Loads and decodes a configuration from a file URL.
    public static func json(
        contentsOf url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> IPAdmissionPolicyConfiguration {
        let data = try Data(contentsOf: url)
        return try json(data: data, decoder: decoder)
    }
}

/// Errors that can occur while compiling external admission policy configuration.
public enum IPAdmissionPolicyConfigurationError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A configured network string could not be parsed as an IPv4 or IPv6 network.
    case invalidNetwork(ruleSet: AdmissionRuleSet, index: Int, value: String)

    public var description: String {
        switch self {
        case .invalidNetwork(let ruleSet, let index, let value):
            return "Invalid \(ruleSet) network at index \(index): \(value)"
        }
    }
}

/// A compiled IP admission policy backed by `swift-cidr` network values.
public struct IPAdmissionPolicy: Sendable, Hashable {
    public let defaultAction: AdmissionAction
    public let allow: [AnyIPNetwork]
    public let deny: [AnyIPNetwork]

    public init(
        allow: [AnyIPNetwork] = [],
        deny: [AnyIPNetwork] = [],
        defaultAction: AdmissionAction = .deny
    ) {
        self.defaultAction = defaultAction
        self.allow = allow
        self.deny = deny
    }

    /// Compiles external configuration into typed CIDR networks.
    public init(configuration: IPAdmissionPolicyConfiguration) throws {
        // parse policy text once at configuration load so admission checks only do typed containment.
        self.init(
            allow: try Self.parse(configuration.allow, ruleSet: .allow),
            deny: try Self.parse(configuration.deny, ruleSet: .deny),
            defaultAction: configuration.defaultAction
        )
    }

    /// Decodes and compiles a JSON configuration from data.
    public init(
        jsonData data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        try self.init(configuration: IPAdmissionPolicyConfiguration.json(data: data, decoder: decoder))
    }

    /// Loads, decodes, and compiles a JSON configuration from a file URL.
    public init(
        contentsOf url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        try self.init(configuration: IPAdmissionPolicyConfiguration.json(contentsOf: url, decoder: decoder))
    }

    /// Evaluates an address and returns the admission action plus reason.
    public func decision(for address: AnyIPAddress) -> AdmissionDecision {
        if let network = deny.first(where: { $0.contains(address) }) {
            // deny rules win on overlap so admission policy fails closed.
            return .deny(reason: .matched(ruleSet: .deny, network: network))
        }

        if let network = allow.first(where: { $0.contains(address) }) {
            return .allow(reason: .matched(ruleSet: .allow, network: network))
        }

        switch defaultAction {
        case .allow:
            return .allow(reason: .defaultAction)
        case .deny:
            return .deny(reason: .defaultAction)
        }
    }

    /// Returns whether an address is allowed by this policy.
    public func allows(_ address: AnyIPAddress) -> Bool {
        decision(for: address).isAllowed
    }

    private static func parse(
        _ values: [String],
        ruleSet: AdmissionRuleSet
    ) throws -> [AnyIPNetwork] {
        try values.enumerated().map { index, value in
            guard let network = AnyIPNetwork(value) else {
                throw IPAdmissionPolicyConfigurationError.invalidNetwork(
                    ruleSet: ruleSet,
                    index: index,
                    value: value
                )
            }

            return network
        }
    }
}
