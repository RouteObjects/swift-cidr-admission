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
import Testing

@testable import CIDRAdmission

@Suite("IP List Text Parser Tests")
struct IPListTextParserTests {
    private let path = "/policies/allow.txt"

    @Test("IP List Text v1 accepts its complete line grammar")
    func completeGrammar() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(
            contentsOf:
                """
                # generated policy\r

                  192.0.2.44   # one host\r
                198.51.100.129/24
                2001:db8::2...2001:db8::7 # inclusive range
                """.utf8
        )

        let rules = try IPListTextParser.parse(data, ruleSet: .allow, path: path)

        #expect(
            rules.map(\.description) == [
                "192.0.2.44",
                "198.51.100.0/24",
                "2001:db8::2...2001:db8::7",
            ]
        )
        guard case .address = rules[0], case .network = rules[1], case .range = rules[2] else {
            Issue.record("Expected address, network, and range rule kinds in source order.")
            return
        }
    }

    @Test("Zero bytes and comment-only input are empty roles")
    func emptyInputs() throws {
        #expect(try IPListTextParser.parse(Data(), ruleSet: .deny, path: path).isEmpty)
        #expect(
            try IPListTextParser.parse(
                Data("\n # comment\r\n".utf8),
                ruleSet: .deny,
                path: path
            ).isEmpty
        )
    }

    @Test("Invalid UTF-8 reports role, path, and line")
    func invalidUTF8() {
        expectFailure(
            Data("192.0.2.1\n".utf8) + Data([0xFF]),
            .invalidUTF8(ruleSet: .allow, path: path, line: 2)
        )
    }

    @Test("Only LF and CRLF line endings are accepted")
    func invalidLineEndings() {
        expectFailure(
            Data("192.0.2.1\r192.0.2.2\n".utf8),
            .invalidLineEnding(ruleSet: .allow, path: path, line: 1)
        )
        expectFailure(
            Data("192.0.2.1\r".utf8),
            .invalidLineEnding(ruleSet: .allow, path: path, line: 1)
        )
        expectFailure(
            Data("192.0.2.1\u{2028}192.0.2.2\n".utf8),
            .invalidLineEnding(ruleSet: .allow, path: path, line: 1)
        )
        expectFailure(
            Data("192.0.2.1\u{0085}\n".utf8),
            .invalidLineEnding(ruleSet: .allow, path: path, line: 1)
        )
    }

    @Test("A byte-order mark is accepted only at byte zero")
    func misplacedByteOrderMark() {
        expectFailure(
            Data("192.0.2.1\n\u{FEFF}192.0.2.2\n".utf8),
            .invalidRule(
                ruleSet: .allow,
                path: path,
                line: 2,
                token: "\u{FEFF}192.0.2.2",
                reason: .misplacedByteOrderMark
            )
        )
        expectFailure(
            Data("# \u{FEFF}metadata\n".utf8),
            .invalidRule(
                ruleSet: .allow,
                path: path,
                line: 1,
                token: "# \u{FEFF}metadata",
                reason: .misplacedByteOrderMark
            )
        )
    }

    @Test("Extra columns report the complete offending token")
    func extraColumns() {
        expectRuleFailure(
            "192.0.2.1 192.0.2.2\n",
            token: "192.0.2.1 192.0.2.2",
            reason: .extraColumns
        )
    }

    @Test("Range-specific failures retain actionable reasons")
    func invalidRanges() {
        expectRuleFailure(
            "192.0.2.1/32...192.0.2.2\n",
            token: "192.0.2.1/32...192.0.2.2",
            reason: .cidrQualifiedRangeEndpoint
        )
        expectRuleFailure(
            "192.0.2.1...2001:db8::1\n",
            token: "192.0.2.1...2001:db8::1",
            reason: .mixedAddressFamilies
        )
        expectRuleFailure(
            "192.0.2.7...192.0.2.2\n",
            token: "192.0.2.7...192.0.2.2",
            reason: .reversedRange
        )
        expectRuleFailure(
            "192.0.2.1......192.0.2.2\n",
            token: "192.0.2.1......192.0.2.2",
            reason: .malformedRange
        )
        expectRuleFailure("...192.0.2.2\n", token: "...192.0.2.2", reason: .malformedRange)
    }

    @Test("Malformed addresses and networks reject the complete parse")
    func malformedValues() {
        expectRuleFailure("not-an-address\n", token: "not-an-address", reason: .malformedValue)
        expectRuleFailure("192.0.2.1/33\n", token: "192.0.2.1/33", reason: .malformedValue)
    }

    private func expectRuleFailure(
        _ text: String,
        token: String,
        reason: IPAdmissionPolicyRuleTextError
    ) {
        expectFailure(
            Data(text.utf8),
            .invalidRule(
                ruleSet: .allow,
                path: path,
                line: 1,
                token: token,
                reason: reason
            )
        )
    }

    private func expectFailure(
        _ data: Data,
        _ expected: IPAdmissionPolicyFileLoadError
    ) {
        do {
            _ = try IPListTextParser.parse(data, ruleSet: .allow, path: path)
            Issue.record("Expected parsing to fail with \(expected).")
        } catch let error as IPAdmissionPolicyFileLoadError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
