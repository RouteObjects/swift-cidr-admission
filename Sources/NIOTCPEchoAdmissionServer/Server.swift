//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Portions of this source file adapt SwiftNIO's NIOTCPEchoServer sample.
//
// Copyright (c) 2026 Craig A. Munro
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
//
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
//
// See SwiftNIO's LICENSE.txt and CONTRIBUTORS.txt for upstream attribution.
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CIDR
import CIDRAdmission
import CIDRNIO
import Foundation
import NIOCore
import NIOPosix

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@main
struct Server {
    private let host: String
    private let port: Int
    private let policy: IPAdmissionPolicy
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    static func main() async throws {
        let options = try ServerOptions.parse(CommandLine.arguments)

        if options.shouldPrintHelp {
            print(ServerOptions.usage)
            return
        }

        let policy = try options.loadPolicy()
        let server = Server(
            host: options.host,
            port: options.port,
            policy: policy,
            eventLoopGroup: .singleton
        )
        try await server.run()
    }

    init(
        host: String,
        port: Int,
        policy: IPAdmissionPolicy,
        eventLoopGroup: MultiThreadedEventLoopGroup
    ) {
        self.host = host
        self.port = port
        self.policy = policy
        self.eventLoopGroup = eventLoopGroup
    }

    func run() async throws {
        let channel = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: host, port: port) { channel in
                configureAcceptedChannel(channel)
            }

        print("Listening on \(host):\(port)")
        print("Admission policy checks the immediate peer before installing the echo pipeline.")

        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await connectionChannel in inbound {
                    group.addTask {
                        print("Handling new connection")
                        await handleConnection(channel: connectionChannel)
                        print("Done handling connection")
                    }
                }
            }
        }
    }

    private func configureAcceptedChannel(
        _ channel: Channel
    ) -> EventLoopFuture<NIOAsyncChannel<String, String>> {
        guard let remoteAddress = channel.remoteAddress else {
            return close(
                channel,
                rejecting: "unknown remote address",
                decision: "deny via missing remote address"
            )
        }

        do {
            let address = try AnyIPAddress(socketAddress: remoteAddress)
            let decision = policy.decision(for: address)

            guard decision.isAllowed else {
                // CHANGE: Admission runs once for the accepted peer before the byte-oriented handlers are installed.
                return close(channel, rejecting: "\(address)", decision: decision.logDescription)
            }

            print("Allowed connection from \(address): \(decision.logDescription)")
        } catch {
            return close(
                channel,
                rejecting: "\(remoteAddress)",
                decision: "deny because remote address could not be converted: \(error)"
            )
        }

        return channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(NewlineDelimiterCoder()))
            try channel.pipeline.syncOperations.addHandler(MessageToByteHandler(NewlineDelimiterCoder()))

            return try NIOAsyncChannel(
                wrappingChannelSynchronously: channel,
                configuration: NIOAsyncChannel.Configuration(
                    inboundType: String.self,
                    outboundType: String.self
                )
            )
        }
    }

    private func close(
        _ channel: Channel,
        rejecting remoteDescription: String,
        decision: String
    ) -> EventLoopFuture<NIOAsyncChannel<String, String>> {
        print("Denied connection from \(remoteDescription): \(decision)")

        return channel.close().flatMapThrowing { () -> NIOAsyncChannel<String, String> in
            throw AdmissionRejected(remoteDescription: remoteDescription, decisionDescription: decision)
        }
    }

    private func handleConnection(channel: NIOAsyncChannel<String, String>) async {
        do {
            try await channel.executeThenClose { inbound, outbound in
                for try await inboundData in inbound {
                    print("Received request (\(inboundData))")
                    try await outbound.write(inboundData)
                }
            }
        } catch {
            print("Hit error: \(error)")
        }
    }
}

private struct ServerOptions: Sendable {
    var host = "127.0.0.1"
    var port = 8765
    var policyURL: URL?
    var shouldPrintHelp = false

    static let usage = """
        Usage: swift run NIOTCPEchoAdmissionServer [--host 127.0.0.1] [--port 8765] [--policy path]

        Options:
          --host <host>      Bind address. Defaults to 127.0.0.1.
          --port <port>      Bind port. Defaults to 8765.
          --policy <path>    JSON admission policy. Defaults to bundled 127.0.0.1/32 allow policy.
          -h, --help         Show this help.
        """

    static func parse(_ arguments: [String]) throws -> ServerOptions {
        var options = ServerOptions()
        var iterator = arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                options.shouldPrintHelp = true

            case "--host":
                guard let value = iterator.next() else {
                    throw UsageError.missingValue(argument)
                }
                options.host = value

            case "--port":
                guard let value = iterator.next() else {
                    throw UsageError.missingValue(argument)
                }
                guard let port = Int(value), (1...65535).contains(port) else {
                    throw UsageError.invalidPort(value)
                }
                options.port = port

            case "--policy":
                guard let value = iterator.next() else {
                    throw UsageError.missingValue(argument)
                }
                options.policyURL = URL(fileURLWithPath: value)

            default:
                throw UsageError.unknownArgument(argument)
            }
        }

        return options
    }

    func loadPolicy() throws -> IPAdmissionPolicy {
        if let policyURL {
            return try IPAdmissionPolicy(contentsOf: policyURL)
        }

        guard let defaultPolicyURL = Bundle.module.url(
            forResource: "default-admission-policy",
            withExtension: "json"
        ) else {
            throw ServerError.defaultPolicyResourceMissing
        }

        // CHANGE: Keep the default policy in data so users can replace it with the same JSON shape.
        return try IPAdmissionPolicy(contentsOf: defaultPolicyURL)
    }
}

private enum UsageError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidPort(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .invalidPort(let value):
            return "Invalid port: \(value)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private enum ServerError: Error, CustomStringConvertible {
    case defaultPolicyResourceMissing

    var description: String {
        switch self {
        case .defaultPolicyResourceMissing:
            return "Bundled default-admission-policy.json was not found"
        }
    }
}

private struct AdmissionRejected: Error, CustomStringConvertible {
    var remoteDescription: String
    var decisionDescription: String

    var description: String {
        "Rejected connection from \(remoteDescription): \(decisionDescription)"
    }
}

private extension AdmissionDecision {
    var logDescription: String {
        switch reason {
        case .matched(let ruleSet, let network):
            return "\(action) via \(ruleSet) rule \(network)"
        case .defaultAction:
            return "\(action) via default action"
        }
    }
}

/// A simple line-based framing codec.
private struct NewlineDelimiterCoder: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = String
    typealias OutboundIn = String

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let newlineIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer.readString(length: newlineIndex - buffer.readerIndex)
            buffer.moveReaderIndex(forwardBy: 1)
            if let line {
                context.fireChannelRead(wrapInboundOut(line))
            }
            return .continue
        } else {
            return .needMoreData
        }
    }

    func encode(data: String, out: inout ByteBuffer) throws {
        out.writeString(data)
        out.writeString("\n")
    }
}
