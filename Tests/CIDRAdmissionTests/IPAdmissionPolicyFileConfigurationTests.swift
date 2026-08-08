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

@Suite("IP Admission Policy File Configuration Tests")
struct IPAdmissionPolicyFileConfigurationTests {
    private let sourceURL = URL(fileURLWithPath: "/policies/allow.txt")
    private let checksumURL = URL(fileURLWithPath: "/policies/allow.txt.sha256")
    private let sourceData = Data("192.0.2.1\n".utf8)
    private let digest = "d1aa74fdddc060ca4e2e10401f2f4e0ef37f94b0d8b25137e8c530d59f4aba75"

    @Test("Configuration requires an explicit checksum policy and defaults safely")
    func configurationDefaults() {
        let configuration = IPAdmissionPolicyFileConfiguration(checksumPolicy: .required)

        #expect(configuration.checksumPolicy == .required)
        #expect(configuration.defaultAction == .deny)
        #expect(configuration.allowFile == nil)
        #expect(configuration.denyFile == nil)
    }

    @Test("An omitted role is empty and performs no filesystem access")
    func omittedRole() throws {
        let access = IPAdmissionPolicyFileAccess(
            openAndRead: { _ in
                Issue.record("Omitted roles must not open the filesystem.")
                return .missing
            }
        )

        let rules = try IPAdmissionPolicyRoleLoader(fileAccess: access).load(
            file: nil,
            ruleSet: .deny,
            checksumPolicy: .required
        )

        #expect(rules.isEmpty)
    }

    @Test("Required verification opens and reads each exact buffer once before parsing")
    func requiredVerification() throws {
        let probe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .data(Data("\(digest)  allow.txt\n".utf8)),
            ]
        )

        let rules = try loader(probe).load(
            file: sourceURL,
            ruleSet: .allow,
            checksumPolicy: .required
        )

        #expect(rules.map(\.description) == ["192.0.2.1"])
        #expect(
            probe.operations == [
                "openAndRead:\(sourceURL.path)",
                "openAndRead:\(checksumURL.path)",
            ]
        )
    }

    @Test("Verify-if-present accepts only an absent detached checksum")
    func verifyIfPresent() throws {
        let missingProbe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .missing,
            ]
        )

        let rules = try loader(missingProbe).load(
            file: sourceURL,
            ruleSet: .allow,
            checksumPolicy: .verifyIfPresent
        )
        #expect(rules.map(\.description) == ["192.0.2.1"])
        #expect(missingProbe.openAndReadCount(for: sourceURL.path) == 1)
        #expect(missingProbe.openAndReadCount(for: checksumURL.path) == 1)

        let malformedProbe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .data(Data("malformed\n".utf8)),
            ]
        )
        expectFailure(
            loader(malformedProbe),
            policy: .verifyIfPresent,
            .checksumMalformed(
                ruleSet: .allow,
                path: sourceURL.path,
                checksumPath: checksumURL.path
            )
        )
    }

    @Test("Required verification rejects a missing checksum")
    func requiredChecksumMissing() {
        let probe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .missing,
            ]
        )

        expectFailure(
            loader(probe),
            policy: .required,
            .checksumNotFound(
                ruleSet: .allow,
                path: sourceURL.path,
                checksumPath: checksumURL.path
            )
        )
    }

    @Test("Unsupported, missing, and non-file sources have distinct errors")
    func sourceKinds() throws {
        let unsupported = try #require(URL(string: "https://example.invalid/allow.txt"))
        let probe = FileAccessProbe(results: [:])
        do {
            _ = try loader(probe).load(
                file: unsupported,
                ruleSet: .deny,
                checksumPolicy: .required
            )
            Issue.record("Expected the network URL to be rejected.")
        } catch let error as IPAdmissionPolicyFileLoadError {
            #expect(
                error
                    == .unsupportedURL(
                        ruleSet: .deny,
                        url: "https://example.invalid/allow.txt"
                    )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let missingProbe = FileAccessProbe(
            results: [sourceURL.path: .missing]
        )
        expectFailure(
            loader(missingProbe),
            policy: .required,
            .fileNotFound(ruleSet: .allow, path: sourceURL.path)
        )

        let nonFileProbe = FileAccessProbe(
            results: [sourceURL.path: .notRegularFile]
        )
        expectFailure(
            loader(nonFileProbe),
            policy: .required,
            .notRegularFile(ruleSet: .allow, path: sourceURL.path)
        )
    }

    @Test("Localhost file URL hosts are accepted with ASCII case insensitivity")
    func uppercaseLocalhost() throws {
        let url = try #require(URL(string: "file://LOCALHOST/policies/allow.txt"))
        let probe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .missing,
            ]
        )

        let rules = try loader(probe).load(
            file: url,
            ruleSet: .allow,
            checksumPolicy: .verifyIfPresent
        )

        #expect(rules.map(\.description) == ["192.0.2.1"])
        #expect(probe.openAndReadCount(for: sourceURL.path) == 1)
    }

    @Test("Injected open/read failures remain role- and path-specific")
    func unreadableSources() {
        let probe = FileAccessProbe(
            results: [:],
            failures: [sourceURL.path]
        )
        expectFailure(
            loader(probe),
            policy: .required,
            .unreadableFile(
                ruleSet: .allow,
                path: sourceURL.path,
                reason: FileAccessProbe.Failure.denied.localizedDescription
            )
        )
    }

    @Test("Unreadable and non-file checksum paths fail even in verify-if-present mode")
    func unusableChecksums() {
        let nonFileProbe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData),
                checksumURL.path: .notRegularFile,
            ]
        )
        expectFailure(
            loader(nonFileProbe),
            policy: .verifyIfPresent,
            .checksumNotRegularFile(
                ruleSet: .allow,
                path: sourceURL.path,
                checksumPath: checksumURL.path
            )
        )

        let readProbe = FileAccessProbe(
            results: [
                sourceURL.path: .data(sourceData)
            ],
            failures: [checksumURL.path]
        )
        expectFailure(
            loader(readProbe),
            policy: .verifyIfPresent,
            .checksumUnreadable(
                ruleSet: .allow,
                path: sourceURL.path,
                checksumPath: checksumURL.path,
                reason: FileAccessProbe.Failure.denied.localizedDescription
            )
        )
    }

    private func loader(_ probe: FileAccessProbe) -> IPAdmissionPolicyRoleLoader {
        IPAdmissionPolicyRoleLoader(
            fileAccess: IPAdmissionPolicyFileAccess(
                openAndRead: { try probe.openAndRead($0) }
            )
        )
    }

    private func expectFailure(
        _ loader: IPAdmissionPolicyRoleLoader,
        policy: IPAdmissionChecksumPolicy,
        _ expected: IPAdmissionPolicyFileLoadError
    ) {
        do {
            _ = try loader.load(file: sourceURL, ruleSet: .allow, checksumPolicy: policy)
            Issue.record("Expected role loading to fail with \(expected).")
        } catch let error as IPAdmissionPolicyFileLoadError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private final class FileAccessProbe: @unchecked Sendable {
    enum Failure: Error {
        case denied
    }

    private let lock = NSLock()
    private let results: [String: IPAdmissionPolicyFileAccess.ReadResult]
    private let failures: Set<String>
    private var recordedOperations: [String] = []

    init(
        results: [String: IPAdmissionPolicyFileAccess.ReadResult],
        failures: Set<String> = []
    ) {
        self.results = results
        self.failures = failures
    }

    var operations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedOperations
    }

    func openAndReadCount(for path: String) -> Int {
        operations.count(where: { $0 == "openAndRead:\(path)" })
    }

    func openAndRead(_ url: URL) throws -> IPAdmissionPolicyFileAccess.ReadResult {
        lock.lock()
        defer { lock.unlock() }
        recordedOperations.append("openAndRead:\(url.path)")
        if failures.contains(url.path) {
            throw Failure.denied
        }
        return results[url.path] ?? .missing
    }
}
