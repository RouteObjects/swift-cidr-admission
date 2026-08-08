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

/// The integrity requirement applied when loading file-backed admission rules.
public enum IPAdmissionChecksumPolicy: Sendable, Hashable {
    /// Verify a detached checksum when it exists, but accept a missing checksum file.
    case verifyIfPresent

    /// Require and verify a detached checksum before parsing the rule file.
    case required
}

/// File-backed allow and deny inputs for an IP admission policy.
///
/// Each configured URL identifies one RouteObjects IP List Text v1 file. An omitted URL means that
/// the corresponding role is empty. File loading is synchronous; applications should construct
/// policies away from event loops and other latency-sensitive executors.
public struct IPAdmissionPolicyFileConfiguration: Sendable, Hashable {
    /// The explicit integrity requirement for every configured file.
    public var checksumPolicy: IPAdmissionChecksumPolicy

    /// The action used when neither role matches an address.
    public var defaultAction: AdmissionAction

    /// The local file that supplies allow rules, or `nil` for an empty allow role.
    public var allowFile: URL?

    /// The local file that supplies deny rules, or `nil` for an empty deny role.
    public var denyFile: URL?

    /// Creates a file-backed policy configuration.
    ///
    /// `checksumPolicy` intentionally has no default so every caller makes an explicit integrity
    /// choice. Production configurations should generally use ``IPAdmissionChecksumPolicy/required``.
    public init(
        checksumPolicy: IPAdmissionChecksumPolicy,
        defaultAction: AdmissionAction = .deny,
        allowFile: URL? = nil,
        denyFile: URL? = nil
    ) {
        self.checksumPolicy = checksumPolicy
        self.defaultAction = defaultAction
        self.allowFile = allowFile
        self.denyFile = denyFile
    }
}

/// The reason a non-comment IP List Text v1 rule is invalid.
public enum IPAdmissionPolicyRuleTextError: Sendable, Hashable, CustomStringConvertible {
    /// The token is not a valid IP address, CIDR network, or range.
    case malformedValue

    /// A range delimiter or endpoint is malformed.
    case malformedRange

    /// At least one range endpoint includes CIDR prefix syntax.
    case cidrQualifiedRangeEndpoint

    /// The two range endpoints use different address families.
    case mixedAddressFamilies

    /// The range's lower endpoint follows its upper endpoint.
    case reversedRange

    /// The line contains more than one whitespace-separated value.
    case extraColumns

    /// A UTF-8 byte-order mark appears anywhere except the beginning of the file.
    case misplacedByteOrderMark

    public var description: String {
        switch self {
        case .malformedValue:
            "expected one IP address, CIDR network, or inclusive range"
        case .malformedRange:
            "expected one strict lower...upper range"
        case .cidrQualifiedRangeEndpoint:
            "range endpoints must be bare addresses without CIDR prefix lengths"
        case .mixedAddressFamilies:
            "range endpoints must use the same IP address family"
        case .reversedRange:
            "range lower endpoint must not follow its upper endpoint"
        case .extraColumns:
            "expected exactly one value before the optional comment"
        case .misplacedByteOrderMark:
            "a UTF-8 byte-order mark is permitted only at the beginning of the file"
        }
    }
}

/// Errors produced while loading and verifying file-backed admission rules.
public enum IPAdmissionPolicyFileLoadError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A configured source uses a URL scheme other than `file`.
    case unsupportedURL(ruleSet: AdmissionRuleSet, url: String)

    /// A configured local source does not exist.
    case fileNotFound(ruleSet: AdmissionRuleSet, path: String)

    /// A configured local source exists but is not a regular file.
    case notRegularFile(ruleSet: AdmissionRuleSet, path: String)

    /// A configured local source could not be inspected or read.
    case unreadableFile(ruleSet: AdmissionRuleSet, path: String, reason: String)

    /// A source line is not valid UTF-8.
    case invalidUTF8(ruleSet: AdmissionRuleSet, path: String, line: Int)

    /// A source line uses a line ending other than LF or CRLF.
    case invalidLineEnding(ruleSet: AdmissionRuleSet, path: String, line: Int)

    /// A non-comment rule token violates RouteObjects IP List Text v1.
    case invalidRule(
        ruleSet: AdmissionRuleSet,
        path: String,
        line: Int,
        token: String,
        reason: IPAdmissionPolicyRuleTextError
    )

    /// Required verification could not find the detached checksum file.
    case checksumNotFound(ruleSet: AdmissionRuleSet, path: String, checksumPath: String)

    /// The detached checksum path exists but is not a regular file.
    case checksumNotRegularFile(ruleSet: AdmissionRuleSet, path: String, checksumPath: String)

    /// A detached checksum file could not be inspected or read.
    case checksumUnreadable(
        ruleSet: AdmissionRuleSet,
        path: String,
        checksumPath: String,
        reason: String
    )

    /// The detached checksum bytes do not use the exact supported syntax.
    case checksumMalformed(ruleSet: AdmissionRuleSet, path: String, checksumPath: String)

    /// The detached checksum names a different artifact.
    case checksumFilenameMismatch(
        ruleSet: AdmissionRuleSet,
        path: String,
        checksumPath: String,
        expected: String,
        actual: String
    )

    /// The rule file's exact bytes do not match the detached SHA-256 digest.
    case checksumDigestMismatch(
        ruleSet: AdmissionRuleSet,
        path: String,
        checksumPath: String,
        expected: String,
        actual: String
    )

    public var description: String {
        switch self {
        case .unsupportedURL(let ruleSet, let url):
            "Unsupported \(ruleSet) file URL \(String(reflecting: url)); only local file URLs are accepted"
        case .fileNotFound(let ruleSet, let path):
            "Missing \(ruleSet) rule file at \(String(reflecting: path))"
        case .notRegularFile(let ruleSet, let path):
            "The \(ruleSet) rule source at \(String(reflecting: path)) is not a regular file"
        case .unreadableFile(let ruleSet, let path, let reason):
            "Unable to read \(ruleSet) rule file at \(String(reflecting: path)): \(reason)"
        case .invalidUTF8(let ruleSet, let path, let line):
            "Invalid UTF-8 in \(ruleSet) rule file \(String(reflecting: path)) at line \(line)"
        case .invalidLineEnding(let ruleSet, let path, let line):
            "Invalid line ending in \(ruleSet) rule file \(String(reflecting: path)) at line \(line); expected LF or CRLF"
        case .invalidRule(let ruleSet, let path, let line, let token, let reason):
            "Invalid \(ruleSet) rule in \(String(reflecting: path)) at line \(line), token \(String(reflecting: token)): \(reason)"
        case .checksumNotFound(let ruleSet, let path, let checksumPath):
            "Missing detached SHA-256 checksum for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath))"
        case .checksumNotRegularFile(let ruleSet, let path, let checksumPath):
            "The detached SHA-256 checksum for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath)) is not a regular file"
        case .checksumUnreadable(let ruleSet, let path, let checksumPath, let reason):
            "Unable to read detached SHA-256 checksum for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath)): \(reason)"
        case .checksumMalformed(let ruleSet, let path, let checksumPath):
            "Malformed detached SHA-256 checksum for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath))"
        case .checksumFilenameMismatch(
            let ruleSet,
            let path,
            let checksumPath,
            let expected,
            let actual
        ):
            "Detached SHA-256 checksum filename mismatch for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath)); expected \(String(reflecting: expected)), found \(String(reflecting: actual))"
        case .checksumDigestMismatch(
            let ruleSet,
            let path,
            let checksumPath,
            let expected,
            let actual
        ):
            "Detached SHA-256 checksum digest mismatch for \(ruleSet) rule file \(String(reflecting: path)) at \(String(reflecting: checksumPath)); expected \(expected), computed \(actual)"
        }
    }
}
