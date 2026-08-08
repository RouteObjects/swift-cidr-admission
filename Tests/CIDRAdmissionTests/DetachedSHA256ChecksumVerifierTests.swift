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

@Suite("Detached SHA-256 Checksum Verifier Tests")
struct DetachedSHA256ChecksumVerifierTests {
    private let sourceData = Data("192.0.2.1\n".utf8)
    private let sourcePath = "/policies/allow list.txt"
    private let checksumPath = "/policies/allow list.txt.sha256"
    private let digest = "d1aa74fdddc060ca4e2e10401f2f4e0ef37f94b0d8b25137e8c530d59f4aba75"

    @Test("Exact lowercase digest, two spaces, basename, and LF verifies")
    func exactFormat() throws {
        try verify(Data("\(digest)  allow list.txt\n".utf8))
    }

    @Test("Malformed detached records are distinguished from mismatches")
    func malformedRecords() {
        let malformed = [
            "\(digest.uppercased())  allow list.txt\n",
            "\(digest) allow list.txt\n",
            "\(digest)  allow list.txt\r\n",
            "\(digest)  allow list.txt",
            "\(digest)  allow list.txt\nextra\n",
            "\(digest)  \n",
        ]

        for record in malformed {
            expectFailure(
                Data(record.utf8),
                .checksumMalformed(
                    ruleSet: .allow,
                    path: sourcePath,
                    checksumPath: checksumPath
                )
            )
        }

        var invalidUTF8Name = Data("\(digest)  ".utf8)
        invalidUTF8Name.append(0xFF)
        invalidUTF8Name.append(0x0A)
        expectFailure(
            invalidUTF8Name,
            .checksumMalformed(ruleSet: .allow, path: sourcePath, checksumPath: checksumPath)
        )
    }

    @Test("A valid record naming another artifact reports filename mismatch")
    func filenameMismatch() {
        expectFailure(
            Data("\(digest)  deny.txt\n".utf8),
            .checksumFilenameMismatch(
                ruleSet: .allow,
                path: sourcePath,
                checksumPath: checksumPath,
                expected: "allow list.txt",
                actual: "deny.txt"
            )
        )
    }

    @Test("A valid record with another digest reports exact-byte mismatch")
    func digestMismatch() {
        let wrongDigest = String(repeating: "0", count: 64)
        expectFailure(
            Data("\(wrongDigest)  allow list.txt\n".utf8),
            .checksumDigestMismatch(
                ruleSet: .allow,
                path: sourcePath,
                checksumPath: checksumPath,
                expected: wrongDigest,
                actual: digest
            )
        )
    }

    @Test("Empty source data uses the standard SHA-256 digest")
    func emptySourceDigest() throws {
        let emptyDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        try DetachedSHA256ChecksumVerifier.verify(
            sourceData: Data(),
            sourcePath: "/policies/empty.txt",
            sourceBasename: "empty.txt",
            checksumData: Data("\(emptyDigest)  empty.txt\n".utf8),
            checksumPath: "/policies/empty.txt.sha256",
            ruleSet: .deny
        )
    }

    private func verify(_ checksumData: Data) throws {
        try DetachedSHA256ChecksumVerifier.verify(
            sourceData: sourceData,
            sourcePath: sourcePath,
            sourceBasename: "allow list.txt",
            checksumData: checksumData,
            checksumPath: checksumPath,
            ruleSet: .allow
        )
    }

    private func expectFailure(
        _ checksumData: Data,
        _ expected: IPAdmissionPolicyFileLoadError
    ) {
        do {
            try verify(checksumData)
            Issue.record("Expected checksum verification to fail with \(expected).")
        } catch let error as IPAdmissionPolicyFileLoadError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
