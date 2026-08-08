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
import CIDRAdmission
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@Suite("IP Admission Policy File Integration Tests")
struct IPAdmissionPolicyFileIntegrationTests {
    @Test("Required checksums load both roles with mixed rule kinds")
    func requiredChecksumsLoadBothRoles() throws {
        try withTemporaryDirectory { directory in
            let allowText =
                "# allow\n"
                + "192.0.2.1\n"
                + "198.51.100.129/24\n"
                + "2001:db8::1...2001:db8::f\n"
            let denyText =
                "# deny\n"
                + "192.0.2.13\n"
                + "2001:db8::8/125\n"
                + "203.0.113.2...203.0.113.7\n"
            let allowURL = try writeList(
                named: "allow.txt",
                text: allowText,
                digest: "80359840b86873a94a18a243ad3f7a5a3ae7510312071584b8413064ce7d6e5c",
                in: directory
            )
            let denyURL = try writeList(
                named: "deny.txt",
                text: denyText,
                digest: "90ec2a73a28012e70459d549c247c1cf8b30238f6479b991987ffff2ce24ca8b",
                in: directory
            )

            let policy = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .required,
                    allowFile: allowURL,
                    denyFile: denyURL
                )
            )

            #expect(
                policy.allow.map(\.description) == [
                    "192.0.2.1",
                    "198.51.100.0/24",
                    "2001:db8::1...2001:db8::f",
                ]
            )
            #expect(
                policy.deny.map(\.description) == [
                    "192.0.2.13",
                    "2001:db8::8/125",
                    "203.0.113.2...203.0.113.7",
                ]
            )
            guard policy.allow.count == 3, policy.deny.count == 3 else {
                Issue.record("Expected three source rules in each role.")
                return
            }
            guard case .address = policy.allow[0],
                case .network = policy.allow[1],
                case .range = policy.allow[2],
                case .address = policy.deny[0],
                case .network = policy.deny[1],
                case .range = policy.deny[2]
            else {
                Issue.record("Expected both roles to preserve address, network, and range kinds.")
                return
            }

            #expect(policy.allows(try #require(AnyIPAddress("192.0.2.1"))))
            #expect(policy.allows(try #require(AnyIPAddress("198.51.100.44"))))
            #expect(!policy.allows(try #require(AnyIPAddress("192.0.2.13"))))
            #expect(policy.allows(try #require(AnyIPAddress("2001:db8::7"))))
            #expect(!policy.allows(try #require(AnyIPAddress("2001:db8::8"))))
            #expect(
                policy.decision(for: try #require(AnyIPAddress("203.0.113.4"))).reason
                    == .matched(ruleSet: .deny, rule: policy.deny[2])
            )
        }
    }

    @Test("Omitted allow and deny roles are independently empty")
    func omittedRoles() throws {
        try withTemporaryDirectory { directory in
            let allowURL = try writeList(
                named: "allow.txt",
                text: "192.0.2.0/24\n",
                digest: "7c05f476485b46ce90b613f8e594ed25245cacfc0337ffb25c47b4771807f6a4",
                in: directory
            )
            let denyURL = try writeList(
                named: "deny.txt",
                text: "203.0.113.0/24\n",
                digest: "29ec405c32c931124f857343346555e0bb1d2864a8ec1aef64e28c37a91d0b8b",
                in: directory
            )

            let allowOnly = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .required,
                    allowFile: allowURL
                )
            )
            #expect(allowOnly.allow.count == 1)
            #expect(allowOnly.deny.isEmpty)
            #expect(allowOnly.allows(try #require(AnyIPAddress("192.0.2.44"))))
            #expect(!allowOnly.allows(try #require(AnyIPAddress("198.51.100.44"))))

            let denyOnly = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .required,
                    defaultAction: .allow,
                    denyFile: denyURL
                )
            )
            #expect(denyOnly.allow.isEmpty)
            #expect(denyOnly.deny.count == 1)
            #expect(!denyOnly.allows(try #require(AnyIPAddress("203.0.113.44"))))
            #expect(denyOnly.allows(try #require(AnyIPAddress("198.51.100.44"))))
        }
    }

    @Test("Verify-if-present accepts a local list without a checksum file")
    func verifyIfPresentWithoutChecksum() throws {
        try withTemporaryDirectory { directory in
            let allowURL = directory.appendingPathComponent("allow.txt")
            try Data("192.0.2.0/24\n".utf8).write(to: allowURL, options: .atomic)

            let policy = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .verifyIfPresent,
                    allowFile: allowURL
                )
            )

            #expect(policy.allow.map(\.description) == ["192.0.2.0/24"])
            #expect(policy.deny.isEmpty)
            #expect(policy.allows(try #require(AnyIPAddress("192.0.2.44"))))
        }
    }

    @Test("A symbolic link to a regular list is read through one pinned descriptor")
    func symbolicLinkToRegularFile() throws {
        try withTemporaryDirectory { directory in
            let targetURL = directory.appendingPathComponent("target.txt")
            let linkURL = directory.appendingPathComponent("allow.txt")
            try Data("192.0.2.0/24\n".utf8).write(to: targetURL, options: .atomic)
            try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

            let policy = try IPAdmissionPolicy(
                fileConfiguration: IPAdmissionPolicyFileConfiguration(
                    checksumPolicy: .verifyIfPresent,
                    allowFile: linkURL
                )
            )

            #expect(policy.allow.map(\.description) == ["192.0.2.0/24"])
        }
    }

    #if os(macOS) || os(Linux)
        @Test("A FIFO source is rejected as non-regular without opening it in blocking mode")
        func fifoIsRejectedWithoutBlocking() throws {
            try withTemporaryDirectory { directory in
                let fifoURL = directory.appendingPathComponent("allow.fifo")
                let result = fifoURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else { return -1 }
                    #if canImport(Darwin)
                        return Darwin.mkfifo(path, mode_t(S_IRUSR | S_IWUSR))
                    #elseif canImport(Glibc)
                        return Glibc.mkfifo(path, mode_t(S_IRUSR | S_IWUSR))
                    #endif
                }
                try #require(result == 0)

                do {
                    _ = try IPAdmissionPolicy(
                        fileConfiguration: IPAdmissionPolicyFileConfiguration(
                            checksumPolicy: .verifyIfPresent,
                            allowFile: fifoURL
                        )
                    )
                    Issue.record("Expected the FIFO to be rejected as a non-regular source.")
                } catch let error as IPAdmissionPolicyFileLoadError {
                    #expect(error == .notRegularFile(ruleSet: .allow, path: fifoURL.path))
                } catch {
                    Issue.record("Unexpected error: \(error)")
                }
            }
        }
    #endif

    @Test("A failing second role returns no partially loaded policy")
    func twoRoleFailureIsAtomic() throws {
        try withTemporaryDirectory { directory in
            let allowURL = try writeList(
                named: "allow.txt",
                text: "192.0.2.0/24\n",
                digest: "7c05f476485b46ce90b613f8e594ed25245cacfc0337ffb25c47b4771807f6a4",
                in: directory
            )
            let denyURL = try writeList(
                named: "deny.txt",
                text: "203.0.113.0/24\n",
                digest: String(repeating: "0", count: 64),
                in: directory
            )
            let expectedError = IPAdmissionPolicyFileLoadError.checksumDigestMismatch(
                ruleSet: .deny,
                path: denyURL.path,
                checksumPath: denyURL.path + ".sha256",
                expected: String(repeating: "0", count: 64),
                actual: "29ec405c32c931124f857343346555e0bb1d2864a8ec1aef64e28c37a91d0b8b"
            )
            var policy: IPAdmissionPolicy?

            do {
                policy = try IPAdmissionPolicy(
                    fileConfiguration: IPAdmissionPolicyFileConfiguration(
                        checksumPolicy: .required,
                        allowFile: allowURL,
                        denyFile: denyURL
                    )
                )
                Issue.record("Expected the invalid deny checksum to reject both roles.")
            } catch let error as IPAdmissionPolicyFileLoadError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            #expect(policy == nil)
        }
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cidr-admission-file-integration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func writeList(
        named basename: String,
        text: String,
        digest: String,
        in directory: URL
    ) throws -> URL {
        let listURL = directory.appendingPathComponent(basename)
        try Data(text.utf8).write(to: listURL, options: .atomic)
        try Data("\(digest)  \(basename)\n".utf8).write(
            to: URL(fileURLWithPath: listURL.path + ".sha256"),
            options: .atomic
        )
        return listURL
    }
}
