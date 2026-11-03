//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Copyright (c) 2026 Craig A. Munro
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CIDRAdmission
import Foundation

struct ClientOptions: Sendable {
    var host = "127.0.0.1"
    var port = 8765
    var message = "hello"
    var allowFile: URL?
    var denyFile: URL?
    var shouldPrintHelp = false

    static let usage = """
        Usage: NIOTCPEgressAdmissionClient [options]

          --host <host>        IP address or hostname. Default: 127.0.0.1.
          --port <port>        TCP port (1...65535). Default: 8765.
          --message <text>     One line, at most 64 KiB in UTF-8. Default: hello.
          --allow-file <path>  IP List Text v1 allow rules; requires <path>.sha256.
          --deny-file <path>   IP List Text v1 deny rules; requires <path>.sha256.
          -h, --help           Show help.

        With no files, the bundled policy allows 127.0.0.1/32 and ::1/128.
        Any custom file replaces the bundled policy; an omitted role is empty.
        Default action is always deny. Deny rules take precedence.
        Connect and echo-response timeouts are each five seconds.
        """

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self()
        var arguments = arguments.makeIterator()
        var seen = Set<String>()
        while let option = arguments.next() {
            if option == "--help" || option == "-h" {
                options.shouldPrintHelp = true
                continue
            }
            guard ["--host", "--port", "--message", "--allow-file", "--deny-file"].contains(option)
            else {
                throw ClientError.usage("Unknown option \(String(reflecting: option))")
            }
            guard seen.insert(option).inserted else {
                throw ClientError.usage("Repeated option \(option)")
            }
            guard let value = arguments.next() else {
                throw ClientError.usage("Missing value for \(option)")
            }
            switch option {
            case "--host":
                guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else {
                    throw ClientError.usage("Host must be a nonempty IP address or hostname")
                }
                options.host = value
            case "--port":
                guard let port = Int(value), (1...65535).contains(port) else {
                    throw ClientError.usage("Port must be an integer in 1...65535")
                }
                options.port = port
            case "--message":
                try LineCodec.validate(value)
                options.message = value
            case "--allow-file", "--deny-file":
                guard !value.isEmpty else { throw ClientError.usage("Empty path for \(option)") }
                let url = URL(fileURLWithPath: value)
                if option == "--allow-file" {
                    options.allowFile = url
                } else {
                    options.denyFile = url
                }
            default:
                preconditionFailure("Validated option was not handled")
            }
        }
        return options
    }

    func loadPolicy() throws -> IPAdmissionPolicy {
        var allowFile = self.allowFile
        if allowFile == nil && denyFile == nil {
            guard
                let bundled = Bundle.module.url(
                    forResource: "allow", withExtension: "txt", subdirectory: "Policy")
            else {
                throw ClientError.bundledPolicyMissing
            }
            allowFile = bundled
        }
        return try IPAdmissionPolicy(
            fileConfiguration: .init(
                checksumPolicy: .required, defaultAction: .deny, allowFile: allowFile,
                denyFile: denyFile
            ))
    }
}

enum ClientError: Error, Sendable, Equatable, CustomStringConvertible {
    case usage(String)
    case bundledPolicyMissing
    case lineBreakInMessage
    case frameTooLarge
    case invalidUTF8
    case prematureEOF
    case mismatchedEcho
    case responseTimeout

    var description: String {
        switch self {
        case .usage(let reason): "\(reason). Use --help for options."
        case .bundledPolicyMissing: "Bundled allow.txt is missing"
        case .lineBreakInMessage: "Messages must not contain CR or LF"
        case .frameTooLarge: "Message exceeds the 64 KiB UTF-8 limit"
        case .invalidUTF8: "Response is not valid UTF-8"
        case .prematureEOF: "Connection closed before a complete echo response"
        case .mismatchedEcho: "Response did not match the sent message"
        case .responseTimeout: "Timed out waiting for the echo response"
        }
    }
}
