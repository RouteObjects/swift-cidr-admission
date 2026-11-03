//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Copyright (c) 2026 Craig A. Munro
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CIDR
import CIDRAdmission
import Foundation
import Testing

@testable import EgressClientExample

@Suite("Egress options and file policy")
struct PolicyAndOptionsTests {
    @Test
    func defaultsAndBundledChecksums() throws {
        let options = try ClientOptions.parse([])
        #expect(options.host == "127.0.0.1")
        #expect(options.port == 8765)
        #expect(options.message == "hello")
        let policy = try options.loadPolicy()
        for text in ["127.0.0.1", "::1"] {
            #expect(policy.allows(try #require(AnyIPAddress(text))))
        }
        for text in ["127.0.0.2", "192.0.2.1", "2001:db8::1"] {
            #expect(!policy.allows(try #require(AnyIPAddress(text))))
        }
        #expect(try ClientOptions.parse(["--help"]).shouldPrintHelp)
        #expect(try ClientOptions.parse(["-h"]).shouldPrintHelp)
    }

    @Test
    func acceptsHostnameAndExplicitOptions() throws {
        let options = try ClientOptions.parse([
            "--host", "echo.example", "--port", "443", "--message", "example",
            "--allow-file", "allow.txt", "--deny-file", "deny.txt",
        ])
        #expect(options.host == "echo.example")
        #expect(options.port == 443)
        #expect(options.message == "example")
        #expect(options.allowFile?.lastPathComponent == "allow.txt")
        #expect(options.denyFile?.lastPathComponent == "deny.txt")
    }

    @Test(arguments: [
        ["--unknown"], ["--port"], ["--port", "0"], ["--port", "65536"], ["--port", "abc"],
        ["--host", ""], ["--host", "two names"], ["--host", "one", "--host", "two"],
        ["--allow-file", ""], ["--message", "line\nbreak"], ["--message", "line\rbreak"],
    ])
    func invalidArguments(arguments: [String]) {
        #expect(throws: ClientError.self) { try ClientOptions.parse(arguments) }
    }

    @Test
    func oversizedMessage() {
        let message = String(repeating: "a", count: LineCodec.maximumLength + 1)
        #expect(throws: ClientError.frameTooLarge) {
            try ClientOptions.parse(["--message", message])
        }
    }

    @Test
    func customFilesReplaceBundledRoles() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let file = try fixture.writeValidList()
        let allowOnly = try ClientOptions(allowFile: file).loadPolicy()
        #expect(allowOnly.allows(try #require(AnyIPAddress("192.0.2.1"))))
        #expect(!allowOnly.allows(try #require(AnyIPAddress("127.0.0.1"))))
        let denyOnly = try ClientOptions(denyFile: file).loadPolicy()
        #expect(!denyOnly.allows(try #require(AnyIPAddress("192.0.2.1"))))
        #expect(!denyOnly.allows(try #require(AnyIPAddress("127.0.0.1"))))
        let both = try ClientOptions(allowFile: file, denyFile: file).loadPolicy()
        #expect(!both.allows(try #require(AnyIPAddress("192.0.2.1"))))
    }

    @Test(arguments: ["missing", "malformed", "mismatch"])
    func rejectsUnverifiedFiles(kind: String) throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let file = try fixture.writeValidList()
        let sidecar = file.appendingPathExtension("sha256")
        switch kind {
        case "missing": try FileManager.default.removeItem(at: sidecar)
        case "malformed": try Data("bad checksum\n".utf8).write(to: sidecar)
        default: try Data("192.0.2.2\n".utf8).write(to: file)
        }
        #expect(throws: IPAdmissionPolicyFileLoadError.self) {
            try ClientOptions(allowFile: file).loadPolicy()
        }
    }
}

struct PolicyFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "egress-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeValidList() throws -> URL {
        let file = directory.appendingPathComponent("allow.txt")
        try Data("192.0.2.1\n".utf8).write(to: file)
        let digest = "d1aa74fdddc060ca4e2e10401f2f4e0ef37f94b0d8b25137e8c530d59f4aba75"
        try Data("\(digest)  allow.txt\n".utf8).write(to: file.appendingPathExtension("sha256"))
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
