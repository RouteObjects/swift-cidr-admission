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
import Foundation

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
    /// The address matched a configured allow or deny source rule.
    case matched(ruleSet: AdmissionRuleSet, rule: AdmissionRule)
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

    /// Loads and decodes a configuration using Foundation URL-loading behavior.
    ///
    /// Do not pass an untrusted or user-controlled URL. Use the local-only file-policy API for
    /// RouteObjects IP List Text v1 inputs.
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

/// A compiled IP admission policy backed by source rules and private exact-coverage indexes.
public struct IPAdmissionPolicy: Sendable, Hashable {
    public let defaultAction: AdmissionAction
    /// Allow rules in their original source order and representation.
    public let allow: [AdmissionRule]
    /// Deny rules in their original source order and representation.
    public let deny: [AdmissionRule]

    private let allowCoverage: IPAdmissionCoverageIndex
    private let denyCoverage: IPAdmissionCoverageIndex

    public init(
        allow: [AnyIPNetwork] = [],
        deny: [AnyIPNetwork] = [],
        defaultAction: AdmissionAction = .deny
    ) {
        self.init(
            allowRules: allow.map(AdmissionRule.network),
            denyRules: deny.map(AdmissionRule.network),
            defaultAction: defaultAction
        )
    }

    /// Creates a policy from representation-aware source rules.
    ///
    /// Both arrays are required so this richer initializer cannot make legacy calls such as
    /// `IPAdmissionPolicy()` or `IPAdmissionPolicy(defaultAction:)` ambiguous.
    public init(
        allowRules: [AdmissionRule],
        denyRules: [AdmissionRule],
        defaultAction: AdmissionAction = .deny
    ) {
        self.defaultAction = defaultAction
        self.allow = allowRules
        self.deny = denyRules
        // Detailed decisions retain source order while the Boolean hot path receives a
        // normalized family-partitioned binary-search index built from the same exact coverage.
        self.allowCoverage = IPAdmissionCoverageIndex(rules: allowRules)
        self.denyCoverage = IPAdmissionCoverageIndex(rules: denyRules)
    }

    /// Compiles external configuration into typed CIDR networks.
    public init(configuration: IPAdmissionPolicyConfiguration) throws {
        // parse policy text once at configuration load so admission checks only do typed containment.
        self.init(
            allowRules: try Self.parse(configuration.allow, ruleSet: .allow),
            denyRules: try Self.parse(configuration.deny, ruleSet: .deny),
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

    /// Loads, decodes, and compiles JSON using Foundation URL-loading behavior.
    ///
    /// Do not pass an untrusted or user-controlled URL. Use ``init(fileConfiguration:)`` for the
    /// local-only list-file path with an explicit checksum policy.
    public init(
        contentsOf url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        try self.init(configuration: IPAdmissionPolicyConfiguration.json(contentsOf: url, decoder: decoder))
    }

    /// Synchronously loads, validates checksums, parses, and compiles separate allow and deny files.
    ///
    /// Construct file-backed policies away from server event loops. Each configured file is read
    /// once. When a checksum is required or present, its digest is matched against the exact bytes
    /// before the same in-memory buffer is parsed. Both roles must succeed before this initializer
    /// returns a policy.
    public init(fileConfiguration: IPAdmissionPolicyFileConfiguration) throws {
        let allowRules = try IPAdmissionPolicyRoleLoader.live.load(
            file: fileConfiguration.allowFile,
            ruleSet: .allow,
            checksumPolicy: fileConfiguration.checksumPolicy
        )
        let denyRules = try IPAdmissionPolicyRoleLoader.live.load(
            file: fileConfiguration.denyFile,
            ruleSet: .deny,
            checksumPolicy: fileConfiguration.checksumPolicy
        )

        // Keep both roles temporary until every read, required checksum validation, and parse passes;
        // a failure in the second role cannot expose a partially compiled policy.
        self.init(
            allowRules: allowRules,
            denyRules: denyRules,
            defaultAction: fileConfiguration.defaultAction
        )
    }

    /// Evaluates an address and returns the admission action plus reason.
    public func decision(for address: AnyIPAddress) -> AdmissionDecision {
        if let rule = deny.first(where: { $0.contains(address) }) {
            // deny rules win on overlap so admission policy fails closed.
            return .deny(reason: .matched(ruleSet: .deny, rule: rule))
        }

        if let rule = allow.first(where: { $0.contains(address) }) {
            return .allow(reason: .matched(ruleSet: .allow, rule: rule))
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
        if denyCoverage.contains(address) {
            return false
        }
        if allowCoverage.contains(address) {
            return true
        }
        return defaultAction == .allow
    }

    private static func parse(
        _ values: [String],
        ruleSet: AdmissionRuleSet
    ) throws -> [AdmissionRule] {
        try values.enumerated().map { index, value in
            guard let network = AnyIPNetwork(value) else {
                throw IPAdmissionPolicyConfigurationError.invalidNetwork(
                    ruleSet: ruleSet,
                    index: index,
                    value: value
                )
            }

            return .network(network)
        }
    }
}
