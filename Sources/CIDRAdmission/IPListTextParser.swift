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

/// Parses one complete RouteObjects IP List Text v1 document without rewriting its source bytes.
enum IPListTextParser {
    private static let byteOrderMark = "\u{FEFF}"
    private static let byteOrderMarkBytes: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func parse(
        _ data: Data,
        ruleSet: AdmissionRuleSet,
        path: String
    ) throws -> [AdmissionRule] {
        guard !data.isEmpty else { return [] }

        var rules: [AdmissionRule] = []
        var lineBytes: [UInt8] = []
        lineBytes.reserveCapacity(128)
        var lineNumber = 1

        for byte in data {
            if byte == 0x0A {
                try parseLine(
                    lineBytes,
                    isLFPresent: true,
                    lineNumber: lineNumber,
                    ruleSet: ruleSet,
                    path: path,
                    into: &rules
                )
                lineBytes.removeAll(keepingCapacity: true)
                lineNumber += 1
            } else {
                lineBytes.append(byte)
            }
        }

        if !lineBytes.isEmpty {
            try parseLine(
                lineBytes,
                isLFPresent: false,
                lineNumber: lineNumber,
                ruleSet: ruleSet,
                path: path,
                into: &rules
            )
        }

        return rules
    }

    private static func parseLine(
        _ sourceBytes: [UInt8],
        isLFPresent: Bool,
        lineNumber: Int,
        ruleSet: AdmissionRuleSet,
        path: String,
        into rules: inout [AdmissionRule]
    ) throws {
        var bytes = sourceBytes
        if isLFPresent, bytes.last == 0x0D {
            bytes.removeLast()
        }

        // Accept only the two line-ending forms in the interchange contract. Silently
        // trimming a lone CR would make verification and human line accounting disagree.
        guard !bytes.contains(0x0D) else {
            throw IPAdmissionPolicyFileLoadError.invalidLineEnding(
                ruleSet: ruleSet,
                path: path,
                line: lineNumber
            )
        }

        if lineNumber == 1, bytes.starts(with: byteOrderMarkBytes) {
            bytes.removeFirst(byteOrderMarkBytes.count)
        }

        guard var line = String(bytes: bytes, encoding: .utf8) else {
            throw IPAdmissionPolicyFileLoadError.invalidUTF8(
                ruleSet: ruleSet,
                path: path,
                line: lineNumber
            )
        }

        // Unicode newline scalars are not alternate horizontal whitespace. Reject them
        // so every logical line is delimited only by the contract's LF or CRLF byte sequences.
        guard !line.unicodeScalars.contains(where: CharacterSet.newlines.contains) else {
            throw IPAdmissionPolicyFileLoadError.invalidLineEnding(
                ruleSet: ruleSet,
                path: path,
                line: lineNumber
            )
        }

        guard !containsByteOrderMark(bytes) else {
            // Foundation consumes a leading BOM while decoding a standalone line. Restore it for
            // an exact token diagnostic when that leading BOM was not at byte zero of the file.
            if bytes.starts(with: byteOrderMarkBytes), !line.hasPrefix(byteOrderMark) {
                line.insert(contentsOf: byteOrderMark, at: line.startIndex)
            }
            let token = diagnosticToken(from: line)
            throw IPAdmissionPolicyFileLoadError.invalidRule(
                ruleSet: ruleSet,
                path: path,
                line: lineNumber,
                token: token,
                reason: .misplacedByteOrderMark
            )
        }

        let uncommented: Substring
        if let commentStart = line.firstIndex(of: "#") {
            uncommented = line[..<commentStart]
        } else {
            uncommented = line[...]
        }

        let token = uncommented.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }

        guard token.rangeOfCharacter(from: .whitespaces) == nil else {
            throw invalidRule(
                .extraColumns,
                ruleSet: ruleSet,
                path: path,
                line: lineNumber,
                token: token
            )
        }

        let rule: AdmissionRule
        if token.contains("...") {
            rule = try parseRange(
                token,
                ruleSet: ruleSet,
                path: path,
                line: lineNumber
            )
        } else if token.contains("/") {
            guard let network = AnyIPNetwork(token) else {
                throw invalidRule(
                    .malformedValue,
                    ruleSet: ruleSet,
                    path: path,
                    line: lineNumber,
                    token: token
                )
            }
            rule = .network(network)
        } else {
            guard let address = AnyIPAddress(token) else {
                throw invalidRule(
                    .malformedValue,
                    ruleSet: ruleSet,
                    path: path,
                    line: lineNumber,
                    token: token
                )
            }
            rule = .address(address)
        }

        rules.append(rule)
    }

    private static func containsByteOrderMark(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= byteOrderMarkBytes.count else { return false }
        for index in 0...(bytes.count - byteOrderMarkBytes.count) {
            if bytes[index..<(index + byteOrderMarkBytes.count)]
                .elementsEqual(byteOrderMarkBytes)
            {
                return true
            }
        }
        return false
    }

    private static func parseRange(
        _ token: String,
        ruleSet: AdmissionRuleSet,
        path: String,
        line: Int
    ) throws -> AdmissionRule {
        guard let delimiter = token.firstRange(of: "..."),
            token[delimiter.upperBound...].firstRange(of: "...") == nil
        else {
            throw invalidRule(
                .malformedRange,
                ruleSet: ruleSet,
                path: path,
                line: line,
                token: token
            )
        }

        let lowerText = String(token[..<delimiter.lowerBound])
        let upperText = String(token[delimiter.upperBound...])
        guard !lowerText.isEmpty, !upperText.isEmpty else {
            throw invalidRule(
                .malformedRange,
                ruleSet: ruleSet,
                path: path,
                line: line,
                token: token
            )
        }

        guard !lowerText.contains("/"), !upperText.contains("/") else {
            throw invalidRule(
                .cidrQualifiedRangeEndpoint,
                ruleSet: ruleSet,
                path: path,
                line: line,
                token: token
            )
        }

        guard let lower = AnyIPAddress(lowerText), let upper = AnyIPAddress(upperText) else {
            throw invalidRule(
                .malformedValue,
                ruleSet: ruleSet,
                path: path,
                line: line,
                token: token
            )
        }

        switch (lower, upper) {
        case (.v4(let lower), .v4(let upper)):
            guard let range = IPv4AddressRange(lowerBound: lower, upperBound: upper) else {
                throw invalidRule(
                    .reversedRange,
                    ruleSet: ruleSet,
                    path: path,
                    line: line,
                    token: token
                )
            }
            return .range(AnyIPAddressRange(range))
        case (.v6(let lower), .v6(let upper)):
            guard let range = IPv6AddressRange(lowerBound: lower, upperBound: upper) else {
                throw invalidRule(
                    .reversedRange,
                    ruleSet: ruleSet,
                    path: path,
                    line: line,
                    token: token
                )
            }
            return .range(AnyIPAddressRange(range))
        case (.v4, .v6), (.v6, .v4):
            throw invalidRule(
                .mixedAddressFamilies,
                ruleSet: ruleSet,
                path: path,
                line: line,
                token: token
            )
        }
    }

    private static func invalidRule(
        _ reason: IPAdmissionPolicyRuleTextError,
        ruleSet: AdmissionRuleSet,
        path: String,
        line: Int,
        token: String
    ) -> IPAdmissionPolicyFileLoadError {
        .invalidRule(
            ruleSet: ruleSet,
            path: path,
            line: line,
            token: token,
            reason: reason
        )
    }

    private static func diagnosticToken(from line: String) -> String {
        let uncommented =
            line.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? ""
        let token = uncommented.trimmingCharacters(in: .whitespaces)
        return token.isEmpty
            ? line.trimmingCharacters(in: .whitespaces)
            : token
    }
}
