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
import NIOCore
import NIOPosix

package enum ClientCommand {
    package static func run(arguments: [String]) async -> Int32 {
        do {
            let options = try ClientOptions.parse(arguments)
            if options.shouldPrintHelp {
                print(ClientOptions.usage)
                return 0
            }
            print(try await EgressClient.run(options: options))
            return 0
        } catch {
            ClientDiagnostics.standardError("Error: \(error)")
            return 1
        }
    }
}

enum ClientDiagnostics {
    static func standardError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum EgressClient {
    static func run(
        options: ClientOptions,
        group: MultiThreadedEventLoopGroup = .singleton,
        resolver: (any Resolver & Sendable)? = nil,
        connectTimeout: TimeAmount = .seconds(5),
        responseTimeout: Duration = .seconds(5),
        log: @escaping @Sendable (String) -> Void = ClientDiagnostics.standardError
    ) async throws -> String {
        try Task.checkCancellation()
        // Integration point 1: Load and verify files once, before DNS or event-loop work.
        let policy = try options.loadPolicy()
        return try await exchange(
            options: options, policy: policy, group: group, resolver: resolver,
            connectTimeout: connectTimeout, responseTimeout: responseTimeout, log: log
        )
    }

    static func exchange(
        options: ClientOptions,
        policy: IPAdmissionPolicy,
        group: MultiThreadedEventLoopGroup = .singleton,
        resolver: (any Resolver & Sendable)? = nil,
        connectTimeout: TimeAmount = .seconds(5),
        responseTimeout: Duration = .seconds(5),
        log: @escaping @Sendable (String) -> Void = ClientDiagnostics.standardError
    ) async throws -> String {
        try Task.checkCancellation()
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(connectTimeout)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    // Integration point 2: Each candidate gets its own pre-connect admission handler.
                    try channel.pipeline.syncOperations.addHandler(
                        EgressAdmissionHandler(policy: policy, log: log))
                }
            }
        if let resolver {
            _ = bootstrap.resolver(resolver)
        }

        // Integration point 6: NIO resolves/races candidates; each concrete connect passes the hook.
        let connection: NIOAsyncChannel<String, String>
        do {
            connection = try await bootstrap.connect(host: options.host, port: options.port) {
                channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(LineCodec()))
                    try channel.pipeline.syncOperations.addHandler(
                        MessageToByteHandler(LineCodec()))
                    return try NIOAsyncChannel(wrappingChannelSynchronously: channel)
                }
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }

        // Integration point 7: Application I/O is async; admission is never repeated for writes.
        return try await connection.executeThenClose { inbound, outbound in
            // NIO's connect bridge is not cancellation-aware. A cancelled connect settles within
            // its timeout; this check then closes the established channel without sending.
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: String.self) { tasks in
                tasks.addTask {
                    try Task.checkCancellation()
                    try await outbound.write(options.message)
                    var iterator = inbound.makeAsyncIterator()
                    let response = try await iterator.next()
                    try Task.checkCancellation()
                    guard let response else { throw ClientError.prematureEOF }
                    guard response == options.message else { throw ClientError.mismatchedEcho }
                    return response
                }
                tasks.addTask {
                    try await Task.sleep(for: responseTimeout)
                    throw ClientError.responseTimeout
                }
                defer { tasks.cancelAll() }
                guard let response = try await tasks.next() else { throw ClientError.prematureEOF }
                return response
            }
        }
    }
}
