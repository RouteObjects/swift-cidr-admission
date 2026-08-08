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
import Testing

@testable import CIDRAdmission

@Suite("Admission Rule Tests")
struct AdmissionRuleTests {
    @Test(
        "Bare addresses preserve address rule kind",
        arguments: [
            ("192.0.2.44", "192.0.2.44"),
            ("2001:0db8:0:0:0:0:0:44", "2001:db8::44"),
        ])
    func bareAddressParsing(input: String, expectedDescription: String) throws {
        let rule = try #require(AdmissionRule(input))

        guard case .address = rule else {
            Issue.record("Expected an address rule for \(input).")
            return
        }
        #expect(rule.description == expectedDescription)
    }

    @Test(
        "CIDR input preserves network kind and canonicalizes host bits",
        arguments: [
            ("192.0.2.129/24", "192.0.2.0/24"),
            ("2001:db8:1::44/48", "2001:db8:1::/48"),
        ])
    func networkParsing(input: String, expectedDescription: String) throws {
        let rule = try #require(AdmissionRule(input))

        guard case .network = rule else {
            Issue.record("Expected a network rule for \(input).")
            return
        }
        #expect(rule.description == expectedDescription)
    }

    @Test(
        "Strict range input preserves range kind",
        arguments: [
            ("192.0.2.2...192.0.2.7", "192.0.2.2...192.0.2.7"),
            ("2001:0db8::2...2001:db8::7", "2001:db8::2...2001:db8::7"),
        ])
    func rangeParsing(input: String, expectedDescription: String) throws {
        let rule = try #require(AdmissionRule(input))

        guard case .range = rule else {
            Issue.record("Expected a range rule for \(input).")
            return
        }
        #expect(rule.description == expectedDescription)
    }

    @Test(
        "Canonical descriptions round-trip losslessly",
        arguments: [
            "192.0.2.44",
            "2001:db8::44",
            "192.0.2.129/24",
            "2001:db8:1::44/48",
            "192.0.2.2...192.0.2.7",
            "2001:db8::2...2001:db8::7",
        ])
    func losslessRoundTrip(input: String) throws {
        let rule = try #require(AdmissionRule(input))

        #expect(AdmissionRule(rule.description) == rule)
    }

    @Test(
        "Malformed and non-strict rule text is rejected",
        arguments: [
            "",
            " 192.0.2.1",
            "192.0.2.1 ",
            "192.0.2.1/33",
            "2001:db8::1/129",
            "192.0.2.7...192.0.2.2",
            "192.0.2.1...2001:db8::1",
            "192.0.2.1/32...192.0.2.2/32",
            "192.0.2.1......192.0.2.2",
            "192.0.2.1 192.0.2.2",
        ])
    func rejectsInvalidText(input: String) {
        #expect(AdmissionRule(input) == nil)
    }

    @Test("Address containment compares literal bits and family")
    func addressContainment() throws {
        let ipv4Rule = AdmissionRule.address(
            .v4(try #require(IPv4Address("192.0.2.44/24")))
        )
        let ipv6Rule = AdmissionRule.address(
            .v6(try #require(IPv6Address("2001:db8::44/64")))
        )

        #expect(ipv4Rule.contains(try #require(AnyIPAddress("192.0.2.44"))))
        #expect(!ipv4Rule.contains(try #require(AnyIPAddress("192.0.2.45"))))
        #expect(!ipv4Rule.contains(try #require(AnyIPAddress("2001:db8::44"))))
        #expect(ipv6Rule.contains(.v6(try #require(IPv6Address("2001:db8::44/96")))))
        #expect(!ipv6Rule.contains(try #require(AnyIPAddress("2001:db8::45"))))
        #expect(!ipv6Rule.contains(try #require(AnyIPAddress("192.0.2.44"))))
    }

    @Test("Programmatic address equality and hashing ignore prefix context")
    func addressEqualityAndHashing() throws {
        let ipv4Host = AdmissionRule.address(.v4(try #require(IPv4Address("192.0.2.44"))))
        let ipv4Context = AdmissionRule.address(.v4(try #require(IPv4Address("192.0.2.44/24"))))
        let ipv6Host = AdmissionRule.address(.v6(try #require(IPv6Address("2001:db8::44"))))
        let ipv6Context = AdmissionRule.address(.v6(try #require(IPv6Address("2001:db8::44/64"))))

        #expect(ipv4Host == ipv4Context)
        #expect(ipv6Host == ipv6Context)
        #expect(Set([ipv4Host, ipv4Context]).count == 1)
        #expect(Set([ipv6Host, ipv6Context]).count == 1)
        #expect(ipv4Context.description == "192.0.2.44")
        #expect(ipv6Context.description == "2001:db8::44")
        #expect(ipv4Host != .network(try #require(AnyIPNetwork("192.0.2.44/32"))))
        #expect(ipv6Host != .range(try #require(AnyIPAddressRange("2001:db8::44...2001:db8::44"))))
    }

    @Test("Network and range containment is inclusive and family-specific")
    func networkAndRangeContainment() throws {
        let ipv4Network = try #require(AdmissionRule("192.0.2.0/24"))
        let ipv6Network = try #require(AdmissionRule("2001:db8::/32"))
        let ipv4Range = try #require(AdmissionRule("198.51.100.2...198.51.100.7"))
        let ipv6Range = try #require(AdmissionRule("2001:db8:1::2...2001:db8:1::7"))

        #expect(ipv4Network.contains(try #require(AnyIPAddress("192.0.2.255"))))
        #expect(!ipv4Network.contains(try #require(AnyIPAddress("192.0.3.0"))))
        #expect(!ipv4Network.contains(try #require(AnyIPAddress("2001:db8::1"))))
        #expect(ipv6Network.contains(try #require(AnyIPAddress("2001:db8:ffff::1"))))
        #expect(!ipv6Network.contains(try #require(AnyIPAddress("2001:db9::1"))))
        #expect(!ipv6Network.contains(try #require(AnyIPAddress("192.0.2.1"))))

        #expect(ipv4Range.contains(try #require(AnyIPAddress("198.51.100.2"))))
        #expect(ipv4Range.contains(try #require(AnyIPAddress("198.51.100.7"))))
        #expect(!ipv4Range.contains(try #require(AnyIPAddress("198.51.100.8"))))
        #expect(ipv6Range.contains(try #require(AnyIPAddress("2001:db8:1::2"))))
        #expect(ipv6Range.contains(try #require(AnyIPAddress("2001:db8:1::7"))))
        #expect(!ipv6Range.contains(try #require(AnyIPAddress("2001:db8:1::8"))))
    }

    @Test("Coverage index partitions and coalesces both address families")
    func coverageIndex() throws {
        let index = IPAdmissionCoverageIndex(rules: [
            .address(.v4(try #require(IPv4Address("192.0.2.1/24")))),
            try #require(AdmissionRule("192.0.2.2...192.0.2.7")),
            try #require(AdmissionRule("192.0.2.8/29")),
            try #require(AdmissionRule("198.51.100.0/24")),
            .address(.v6(try #require(IPv6Address("2001:db8::1/64")))),
            try #require(AdmissionRule("2001:db8::2...2001:db8::7")),
            try #require(AdmissionRule("2001:db8::8/125")),
            try #require(AdmissionRule("2001:db8:ffff::1...2001:db8:ffff::3")),
        ])

        #expect(index.contains(try #require(AnyIPAddress("192.0.2.1"))))
        #expect(index.contains(try #require(AnyIPAddress("192.0.2.15"))))
        #expect(!index.contains(try #require(AnyIPAddress("192.0.2.16"))))
        #expect(index.contains(try #require(AnyIPAddress("198.51.100.255"))))
        #expect(index.contains(try #require(AnyIPAddress("2001:db8::1"))))
        #expect(index.contains(try #require(AnyIPAddress("2001:db8::f"))))
        #expect(!index.contains(try #require(AnyIPAddress("2001:db8::10"))))
        #expect(index.contains(try #require(AnyIPAddress("2001:db8:ffff::3"))))
    }

    @Test("Empty coverage index matches neither family")
    func emptyCoverageIndex() throws {
        let index = IPAdmissionCoverageIndex(rules: [])

        #expect(!index.contains(try #require(AnyIPAddress("192.0.2.1"))))
        #expect(!index.contains(try #require(AnyIPAddress("2001:db8::1"))))
    }
}
