import Foundation
import Testing
import CIDR
import CIDRAdmission

@Suite("IP Admission Policy Tests")
struct IPAdmissionPolicyTests {
    @Test("IPv4 allow rule permits matching address")
    func ipv4AllowRule() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("192.0.2.0/24"))]
        )

        let address = try #require(AnyIPAddress("192.0.2.10"))

        #expect(policy.allows(address))
        #expect(policy.decision(for: address).action == .allow)
    }

    @Test("IPv6 allow rule permits matching address")
    func ipv6AllowRule() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("2001:db8::/32"))]
        )

        let address = try #require(AnyIPAddress("2001:db8::1"))

        #expect(policy.allows(address))
        #expect(policy.decision(for: address).action == .allow)
    }

    @Test("Deny rule rejects matching address")
    func denyRule() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("192.0.2.0/24"))],
            deny: [try #require(AnyIPNetwork("192.0.2.13/32"))]
        )

        let address = try #require(AnyIPAddress("192.0.2.13"))

        #expect(!policy.allows(address))
        #expect(policy.decision(for: address).action == .deny)
    }

    @Test("Deny rule wins over overlapping allow rule")
    func denyWinsOverAllow() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("10.0.0.0/8"))],
            deny: [try #require(AnyIPNetwork("10.0.5.13/32"))]
        )

        let address = try #require(AnyIPAddress("10.0.5.13"))

        guard case .deny(let reason) = policy.decision(for: address) else {
            Issue.record("Expected deny decision.")
            return
        }

        #expect(reason == .matched(ruleSet: .deny, network: try #require(AnyIPNetwork("10.0.5.13/32"))))
    }

    @Test("Default deny rejects unmatched address")
    func defaultDeny() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("192.0.2.0/24"))]
        )

        let address = try #require(AnyIPAddress("198.51.100.1"))

        #expect(!policy.allows(address))
        #expect(policy.decision(for: address) == .deny(reason: .defaultAction))
    }

    @Test("Default allow permits unmatched address")
    func defaultAllow() throws {
        let policy = IPAdmissionPolicy(defaultAction: .allow)
        let address = try #require(AnyIPAddress("203.0.113.10"))

        #expect(policy.allows(address))
        #expect(policy.decision(for: address) == .allow(reason: .defaultAction))
    }

    @Test("Mixed-family rules do not match")
    func mixedFamilyRulesDoNotMatch() throws {
        let policy = IPAdmissionPolicy(
            allow: [try #require(AnyIPNetwork("2001:db8::/32"))]
        )

        let address = try #require(AnyIPAddress("192.0.2.10"))

        #expect(!policy.allows(address))
    }

    @Test("Exact host networks match IPv4 and IPv6 addresses")
    func exactHostNetworksMatch() throws {
        let policy = IPAdmissionPolicy(
            allow: [
                try #require(AnyIPNetwork("192.0.2.44/32")),
                try #require(AnyIPNetwork("2001:db8::44/128")),
            ]
        )

        #expect(policy.allows(try #require(AnyIPAddress("192.0.2.44"))))
        #expect(policy.allows(try #require(AnyIPAddress("2001:db8::44"))))
        #expect(!policy.allows(try #require(AnyIPAddress("192.0.2.45"))))
        #expect(!policy.allows(try #require(AnyIPAddress("2001:db8::45"))))
    }

    @Test("JSON data decodes and compiles policy")
    func jsonDataConfiguration() throws {
        let json = """
        {
          "defaultAction": "deny",
          "allow": ["10.0.0.0/8", "2001:db8::/32"],
          "deny": ["10.0.5.13/32"]
        }
        """.data(using: .utf8)!

        let policy = try IPAdmissionPolicy(jsonData: json)

        #expect(policy.allows(try #require(AnyIPAddress("10.0.5.12"))))
        #expect(!policy.allows(try #require(AnyIPAddress("10.0.5.13"))))
        #expect(policy.allows(try #require(AnyIPAddress("2001:db8::1"))))
        #expect(!policy.allows(try #require(AnyIPAddress("198.51.100.1"))))
    }

    @Test("JSON file URL decodes and compiles policy")
    func jsonFileConfiguration() throws {
        let json = """
        {
          "defaultAction": "allow",
          "deny": ["203.0.113.0/24"]
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cidr-admission-policy-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let policy = try IPAdmissionPolicy(contentsOf: url)

        #expect(!policy.allows(try #require(AnyIPAddress("203.0.113.10"))))
        #expect(policy.allows(try #require(AnyIPAddress("198.51.100.10"))))
    }

    @Test("Invalid CIDR text reports rule set and index")
    func invalidCIDRReportsContext() throws {
        let configuration = IPAdmissionPolicyConfiguration(
            allow: ["192.0.2.0/24"],
            deny: ["not-a-network"]
        )

        do {
            _ = try IPAdmissionPolicy(configuration: configuration)
            Issue.record("Expected invalid CIDR configuration to throw.")
        } catch let error as IPAdmissionPolicyConfigurationError {
            #expect(error == .invalidNetwork(ruleSet: .deny, index: 0, value: "not-a-network"))
        }
    }
}
