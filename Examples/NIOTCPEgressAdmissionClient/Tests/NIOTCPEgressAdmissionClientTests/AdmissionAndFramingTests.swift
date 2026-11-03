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
import NIOCore
import NIOEmbedded
import Synchronization
import Testing

@testable import EgressClientExample

@Suite("Egress connect boundary")
struct AdmissionHandlerTests {
    @Test(arguments: ["127.0.0.1", "::1"])
    func allowedConnectionAndWrites(ip: String) throws {
        let policy = try IPAdmissionPolicy(
            configuration: .init(allow: ["127.0.0.1/32", "::1/128"]))
        let probe = ConnectProbe()
        let logs = Mutex<[String]>([])
        let channel = EmbeddedChannel(handlers: [
            probe,
            EgressAdmissionHandler(policy: policy) { message in
                logs.withLock { $0.append(message) }
            },
        ])
        defer { _ = try? channel.finish(acceptAlreadyClosed: true) }
        let destination = try SocketAddress(ipAddress: ip, port: 8765)
        let promise = channel.eventLoop.makePromise(of: Void.self)
        let outcome = Mutex<Result<Void, any Error>?>(nil)
        promise.futureResult.whenComplete { result in outcome.withLock { $0 = result } }
        channel.connect(to: destination, promise: promise)
        channel.embeddedEventLoop.run()
        #expect(probe.destinations == [destination])
        #expect(probe.promise?.futureResult === promise.futureResult)
        try #require(outcome.withLock { $0 }).get()

        for text in ["one", "two"] {
            let buffer = ByteBuffer(string: text)
            try channel.writeOutbound(buffer)
            #expect(try channel.readOutbound(as: ByteBuffer.self) == buffer)
        }
        #expect(logs.withLock { $0.count } == 1)
    }

    @Test(arguments: ["127.0.0.1", "::1"])
    func rejectedDestinationsNeverConnect(ip: String) throws {
        for configuration in [
            IPAdmissionPolicyConfiguration(),
            .init(allow: ["0.0.0.0/0", "::/0"], deny: [ip + (ip.contains(":") ? "/128" : "/32")]),
        ] {
            let probe = ConnectProbe()
            let policy = try IPAdmissionPolicy(configuration: configuration)
            let channel = EmbeddedChannel(handlers: [
                probe, EgressAdmissionHandler(policy: policy, log: { _ in }),
            ])
            defer { _ = try? channel.finish(acceptAlreadyClosed: true) }
            let outcome = Mutex<Result<Void, any Error>?>(nil)
            let promise = channel.eventLoop.makePromise(of: Void.self)
            promise.futureResult.whenComplete { result in outcome.withLock { $0 = result } }
            channel.connect(to: try SocketAddress(ipAddress: ip, port: 8765), promise: promise)
            channel.embeddedEventLoop.run()
            #expect(probe.destinations.isEmpty)
            #expect(!channel.isActive)
            let result = try #require(outcome.withLock { $0 })
            #expect(throws: EgressAdmissionError.self) { try result.get() }
        }
    }

    @Test
    func unsupportedAddressFailsClosed() throws {
        let policy = try IPAdmissionPolicy(configuration: .init(defaultAction: .allow))
        let probe = ConnectProbe()
        let channel = EmbeddedChannel(handlers: [
            probe, EgressAdmissionHandler(policy: policy, log: { _ in }),
        ])
        defer { _ = try? channel.finish(acceptAlreadyClosed: true) }
        let outcome = Mutex<Result<Void, any Error>?>(nil)
        let promise = channel.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { result in outcome.withLock { $0 = result } }
        channel.connect(
            to: try SocketAddress(unixDomainSocketPath: "/tmp/egress-unsupported"), promise: promise
        )
        channel.embeddedEventLoop.run()
        #expect(probe.destinations.isEmpty)
        #expect(!channel.isActive)
        let result = try #require(outcome.withLock { $0 })
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test
    func denialWithoutPromiseStillCloses() throws {
        let policy = try IPAdmissionPolicy(configuration: .init())
        let probe = ConnectProbe()
        let channel = EmbeddedChannel(handlers: [
            probe, EgressAdmissionHandler(policy: policy, log: { _ in }),
        ])
        defer { _ = try? channel.finish(acceptAlreadyClosed: true) }
        let closed = Mutex(false)
        channel.closeFuture.whenSuccess { closed.withLock { $0 = true } }
        channel.connect(to: try SocketAddress(ipAddress: "127.0.0.1", port: 8765), promise: nil)
        channel.embeddedEventLoop.run()
        #expect(probe.destinations.isEmpty)
        #expect(!channel.isActive)
        #expect(closed.withLock { $0 })
    }
}

private final class ConnectProbe: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    var destinations: [SocketAddress] = []
    var promise: EventLoopPromise<Void>?

    func connect(
        context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?
    ) {
        destinations.append(address)
        self.promise = promise
        promise?.succeed(())
    }
}

@Suite("Bounded echo framing")
struct LineCodecTests {
    @Test
    func fragmentedAndCoalescedFrames() throws {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(LineCodec()))
        defer { _ = try? channel.finish() }
        try channel.writeInbound(ByteBuffer(string: "hel"))
        #expect(try channel.readInbound(as: String.self) == nil)
        try channel.writeInbound(ByteBuffer(string: "lo\nworld\n"))
        #expect(try channel.readInbound(as: String.self) == "hello")
        #expect(try channel.readInbound(as: String.self) == "world")
    }

    @Test
    func exactLimitAndDelimiter() throws {
        let channel = EmbeddedChannel(handlers: [
            ByteToMessageHandler(LineCodec()), MessageToByteHandler(LineCodec()),
        ])
        defer { _ = try? channel.finish() }
        let message = String(repeating: "a", count: LineCodec.maximumLength)
        try channel.writeInbound(ByteBuffer(string: message))
        #expect(try channel.readInbound(as: String.self) == nil)
        try channel.writeInbound(ByteBuffer(string: "\n"))
        #expect(try channel.readInbound(as: String.self) == message)
        try channel.writeOutbound(message)
        #expect(try channel.readOutbound(as: ByteBuffer.self) == ByteBuffer(string: message + "\n"))
    }

    @Test(arguments: [false, true])
    func oversizedInbound(withDelimiter: Bool) throws {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(LineCodec()))
        defer { _ = try? channel.finish() }
        let frame =
            String(repeating: "a", count: LineCodec.maximumLength + 1) + (withDelimiter ? "\n" : "")
        #expect(throws: ClientError.frameTooLarge) {
            try channel.writeInbound(ByteBuffer(string: frame))
        }
    }

    @Test
    func rejectsInvalidTextAndIncompleteFrame() throws {
        for bytes in [[UInt8(0xff), 10], Array("hi\r\n".utf8)] {
            let channel = EmbeddedChannel(handler: ByteToMessageHandler(LineCodec()))
            defer { _ = try? channel.finish() }
            #expect(throws: ClientError.self) { try channel.writeInbound(ByteBuffer(bytes: bytes)) }
        }
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(LineCodec()))
        try channel.writeInbound(ByteBuffer(string: "incomplete"))
        #expect(throws: ClientError.prematureEOF) { try channel.finish() }
    }
}
