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

import CIDRAdmission
import Crypto
import Foundation

final class FilePolicyBenchmarkFixtureStore {
    let fixtures: [FilePolicyBenchmarkFixture]
    private let directoryOwner: FilePolicyBenchmarkDirectory

    init(sizes: [Int]) throws {
        let directoryOwner = try FilePolicyBenchmarkDirectory()
        self.directoryOwner = directoryOwner

        var fixtures: [FilePolicyBenchmarkFixture] = []
        fixtures.reserveCapacity(sizes.count * 4)
        for size in sizes {
            for family in FilePolicyBenchmarkFamily.allCases {
                for representation in FilePolicyBenchmarkRepresentation.allCases {
                    fixtures.append(
                        try FilePolicyBenchmarkFixture(
                            directoryOwner: directoryOwner,
                            family: family,
                            representation: representation,
                            ruleCount: size
                        )
                    )
                }
            }
        }
        self.fixtures = fixtures
    }
}

private final class FilePolicyBenchmarkDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cidr-admission-benchmarks-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct FilePolicyBenchmarkFixture {
    let family: String
    let representation: String
    let ruleCount: Int

    private let requiredURL: URL
    private let verifyIfPresentURL: URL
    // CHANGE: Keep generated files alive for as long as any registered benchmark closure.
    private let directoryOwner: FilePolicyBenchmarkDirectory

    fileprivate init(
        directoryOwner: FilePolicyBenchmarkDirectory,
        family: FilePolicyBenchmarkFamily,
        representation: FilePolicyBenchmarkRepresentation,
        ruleCount: Int
    ) throws {
        self.family = family.rawValue
        self.representation = representation.rawValue
        self.ruleCount = ruleCount
        self.directoryOwner = directoryOwner

        let data = Data(
            family.rules(count: ruleCount, representation: representation)
                .joined(separator: "\n")
                .appending("\n")
                .utf8
        )
        let stem = "\(family.rawValue)-\(representation.rawValue)-\(ruleCount)"
        self.requiredURL = directoryOwner.url.appendingPathComponent("\(stem)-required.txt")
        self.verifyIfPresentURL = directoryOwner.url.appendingPathComponent("\(stem)-unchecked.txt")
        try data.write(to: requiredURL)
        try data.write(to: verifyIfPresentURL)

        let checksumURL = URL(fileURLWithPath: requiredURL.path + ".sha256")
        let checksum = Self.detachedChecksum(
            for: data,
            filename: requiredURL.lastPathComponent
        )
        try checksum.write(to: checksumURL)
    }

    func load(checksumPolicy: IPAdmissionChecksumPolicy) throws -> IPAdmissionPolicy {
        let file = checksumPolicy == .required ? requiredURL : verifyIfPresentURL
        return try IPAdmissionPolicy(
            fileConfiguration: IPAdmissionPolicyFileConfiguration(
                checksumPolicy: checksumPolicy,
                allowFile: file
            )
        )
    }

    private static func detachedChecksum(for data: Data, filename: String) -> Data {
        let alphabet: [UInt8] = Array("0123456789abcdef".utf8)
        let digest = SHA256.hash(data: data)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64 + 2 + filename.utf8.count + 1)
        for byte in digest {
            bytes.append(alphabet[Int(byte >> 4)])
            bytes.append(alphabet[Int(byte & 0x0F)])
        }
        bytes.append(contentsOf: [0x20, 0x20])
        bytes.append(contentsOf: filename.utf8)
        bytes.append(0x0A)
        return Data(bytes)
    }
}

enum FilePolicyBenchmarkFamily: String, CaseIterable {
    case v4
    case v6

    func rules(
        count: Int,
        representation: FilePolicyBenchmarkRepresentation
    ) -> [String] {
        switch (self, representation) {
        case (.v4, .cidr):
            (0..<count).map { index in
                let slot = index * 2
                return "10.\(slot / 256).\(slot % 256).0/24"
            }
        case (.v4, .ranges):
            (0..<count).map { index in
                let slot = index * 2
                let prefix = "10.\(slot / 256).\(slot % 256)"
                return "\(prefix).0...\(prefix).255"
            }
        case (.v6, .cidr):
            (0..<count).map { index in
                "2001:db8:\(String(index * 2, radix: 16))::/112"
            }
        case (.v6, .ranges):
            (0..<count).map { index in
                let prefix = "2001:db8:\(String(index * 2, radix: 16))"
                return "\(prefix)::...\(prefix)::ffff"
            }
        }
    }
}

enum FilePolicyBenchmarkRepresentation: String, CaseIterable {
    case ranges
    case cidr
}
