//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Copyright (c) 2026 Craig A. Munro
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOPosix
import Synchronization
import Testing

@testable import EgressClientExample

enum TestSupportError: Error { case deadline, ended }

func within<Value: Sendable>(
    _ timeout: Duration = .seconds(3),
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestSupportError.deadline
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TestSupportError.ended }
        return result
    }
}

func nextEvent(_ events: AsyncStream<Void>) async throws {
    try await within {
        var iterator = events.makeAsyncIterator()
        guard await iterator.next() != nil else { throw TestSupportError.ended }
    }
}

final class LocalServer: Sendable {
    enum Mode: Sendable { case echo, fragmented, eof, partialEOF, mismatch, silent, oversized }
    final class State: Sendable {
        let children = Mutex<[any Channel]>([])
        let receivedBytes = Mutex(0)
        let received = AsyncStream<Void>.makeStream()
        let closed = AsyncStream<Void>.makeStream()
    }

    let listener: any Channel
    let state: State
    let port: Int

    private init(listener: any Channel, state: State, port: Int) {
        self.listener = listener
        self.state = state
        self.port = port
    }

    static func start(_ mode: Mode, host: String = "127.0.0.1") async throws -> LocalServer {
        let state = State()
        let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(Peer(mode: mode, state: state))
                }
            }
            .bind(host: host, port: 0).get()
        let port = try #require(listener.localAddress?.port)
        return LocalServer(listener: listener, state: state, port: port)
    }

    func stop() async {
        try? await listener.close().get()
        for channel in state.children.withLock({ $0 }) {
            channel.close(promise: nil)
            try? await channel.closeFuture.get()
        }
        state.received.continuation.finish()
        state.closed.continuation.finish()
    }

    private final class Peer: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer
        let mode: Mode
        let state: State

        init(mode: Mode, state: State) {
            self.mode = mode
            self.state = state
        }

        func channelActive(context: ChannelHandlerContext) {
            state.children.withLock { $0.append(context.channel) }
            context.fireChannelActive()
        }

        func channelInactive(context: ChannelHandlerContext) {
            state.closed.continuation.yield(())
            context.fireChannelInactive()
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            state.receivedBytes.withLock { $0 += buffer.readableBytes }
            state.received.continuation.yield(())
            switch mode {
            case .echo: context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
            case .fragmented:
                if let first = buffer.readSlice(length: 1) {
                    context.writeAndFlush(wrapOutboundOut(first), promise: nil)
                }
                context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
            case .eof: context.close(promise: nil)
            case .partialEOF:
                let channel = context.channel
                context.writeAndFlush(wrapOutboundOut(ByteBuffer(string: "partial"))).whenComplete {
                    _ in
                    channel.close(promise: nil)
                }
            case .mismatch:
                context.writeAndFlush(
                    wrapOutboundOut(ByteBuffer(string: "not the echo\n")), promise: nil)
            case .silent: break
            case .oversized:
                let frame = String(repeating: "a", count: LineCodec.maximumLength + 1) + "\n"
                context.writeAndFlush(wrapOutboundOut(ByteBuffer(string: frame)), promise: nil)
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: any Error) {
            context.close(promise: nil)
        }
    }
}

func withServer(
    _ mode: LocalServer.Mode,
    host: String = "127.0.0.1",
    body: (LocalServer) async throws -> Void
) async throws {
    let server = try await LocalServer.start(mode, host: host)
    do {
        try await body(server)
        await server.stop()
    } catch {
        await server.stop()
        throw error
    }
}

// The resolver never performs DNS. Its A response is explicitly released by the test.
final class ControlledResolver: Resolver, Sendable {
    let loop: any EventLoop
    let aPromise: EventLoopPromise<[SocketAddress]>
    let ipv6: [SocketAddress]
    let queries = Mutex(0)
    let started = AsyncStream<Void>.makeStream()
    private let completed = Mutex(false)

    init(ipv6: [SocketAddress] = []) {
        loop = MultiThreadedEventLoopGroup.singleton.next()
        aPromise = loop.makePromise()
        self.ipv6 = ipv6
    }

    func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        queries.withLock { $0 += 1 }
        started.continuation.yield(())
        return aPromise.futureResult
    }

    func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        queries.withLock { $0 += 1 }
        return loop.makeSucceededFuture(ipv6)
    }

    func completeA(_ result: Result<[SocketAddress], any Error>) {
        let first = completed.withLock { done in
            if done { return false }
            done = true
            return true
        }
        if first { aPromise.completeWith(result) }
    }

    func cancelQueries() {
        completeA(.failure(CancellationError()))
        started.continuation.finish()
    }
}
