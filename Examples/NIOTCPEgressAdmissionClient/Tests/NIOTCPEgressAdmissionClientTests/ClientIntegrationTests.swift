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
import Synchronization
import Testing

@testable import EgressClientExample

@Suite("Async egress client", .timeLimit(.minutes(1)))
struct ClientIntegrationTests {
    @Test(arguments: [LocalServer.Mode.echo, .fragmented])
    func successfulExchangeAndCleanup(mode: LocalServer.Mode) async throws {
        try await withServer(mode) { server in
            let response = try await EgressClient.run(
                options: .init(port: server.port), log: { _ in })
            #expect(response == "hello")
            try await nextEvent(server.state.closed.stream)
            #expect(server.state.receivedBytes.withLock { $0 } == 6)
        }
    }

    @Test
    func ipv6Exchange() async throws {
        try await withServer(.echo, host: "::1") { server in
            #expect(
                try await EgressClient.run(
                    options: .init(host: "::1", port: server.port), log: { _ in })
                    == "hello")
            try await nextEvent(server.state.closed.stream)
        }
    }

    @Test
    func deniedDNSCandidateFallsBackToAllowedCandidate() async throws {
        try await withServer(.echo) { server in
            let denied = try SocketAddress(ipAddress: "::1", port: server.port)
            let allowed = try SocketAddress(ipAddress: "127.0.0.1", port: server.port)
            let resolver = ControlledResolver(ipv6: [denied])
            defer { resolver.cancelQueries() }
            let policy = try IPAdmissionPolicy(configuration: .init(allow: ["127.0.0.1/32"]))
            let logs = Mutex<[String]>([])
            let response = try await EgressClient.exchange(
                options: .init(host: "echo.example", port: server.port), policy: policy,
                resolver: resolver
            ) { message in
                logs.withLock { $0.append(message) }
                if message.hasPrefix("Denied") { resolver.completeA(.success([allowed])) }
            }
            #expect(response == "hello")
            #expect(logs.withLock { $0.filter { $0.hasPrefix("Denied") }.count } == 1)
            #expect(logs.withLock { $0.filter { $0.hasPrefix("Allowed") }.count } == 1)
            try await nextEvent(server.state.closed.stream)
            #expect(server.state.children.withLock { $0.count } == 1)
        }
    }

    @Test
    func allDNSCandidatesDenied() async throws {
        try await withServer(.echo) { server in
            let resolver = ControlledResolver(ipv6: [
                try SocketAddress(ipAddress: "::1", port: server.port)
            ])
            defer { resolver.cancelQueries() }
            resolver.completeA(
                .success([try SocketAddress(ipAddress: "127.0.0.1", port: server.port)]))
            let policy = try IPAdmissionPolicy(configuration: .init())
            let logs = Mutex<[String]>([])
            await #expect(throws: (any Error).self) {
                try await EgressClient.exchange(
                    options: .init(host: "denied.example", port: server.port), policy: policy,
                    resolver: resolver,
                    log: { message in logs.withLock { $0.append(message) } }
                )
            }
            #expect(logs.withLock { $0.count } == 2)
            #expect(logs.withLock { $0.allSatisfy { $0.hasPrefix("Denied") } })
            #expect(server.state.children.withLock { $0.isEmpty })
        }
    }

    @Test(arguments: [LocalServer.Mode.eof, .partialEOF, .mismatch, .oversized])
    func responseFailuresCloseChannel(mode: LocalServer.Mode) async throws {
        try await withServer(mode) { server in
            let expected: ClientError
            switch mode {
            case .mismatch: expected = .mismatchedEcho
            case .oversized: expected = .frameTooLarge
            default: expected = .prematureEOF
            }
            await #expect(throws: expected) {
                try await EgressClient.run(options: .init(port: server.port), log: { _ in })
            }
            try await nextEvent(server.state.closed.stream)
        }
    }

    @Test
    func responseDeadlineClosesSilentPeer() async throws {
        try await withServer(.silent) { server in
            await #expect(throws: ClientError.responseTimeout) {
                try await EgressClient.run(
                    options: .init(port: server.port), responseTimeout: .milliseconds(100),
                    log: { _ in })
            }
            try await nextEvent(server.state.closed.stream)
        }
    }

    @Test
    func cancellationDuringResponseClosesChannel() async throws {
        try await withServer(.silent) { server in
            let task = Task {
                try await EgressClient.run(options: .init(port: server.port), log: { _ in })
            }
            do { try await nextEvent(server.state.received.stream) } catch {
                task.cancel()
                _ = await task.result
                throw error
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            try await nextEvent(server.state.closed.stream)
        }
    }

    @Test
    func cancelledConnectSettlesWithoutSending() async throws {
        try await withServer(.echo) { server in
            let resolver = ControlledResolver()
            defer { resolver.cancelQueries() }
            let task = Task {
                try await EgressClient.run(
                    options: .init(host: "cancel.example", port: server.port), resolver: resolver,
                    log: { _ in })
            }
            do { try await nextEvent(resolver.started.stream) } catch {
                task.cancel()
                resolver.cancelQueries()
                _ = await task.result
                throw error
            }
            task.cancel()
            resolver.completeA(
                .success([try SocketAddress(ipAddress: "127.0.0.1", port: server.port)]))
            await #expect(throws: CancellationError.self) { try await task.value }
            try await nextEvent(server.state.closed.stream)
            #expect(server.state.receivedBytes.withLock { $0 } == 0)
        }
    }

    @Test
    func connectTimeoutBoundsUnresolvedCandidate() async throws {
        let resolver = ControlledResolver()
        defer { resolver.cancelQueries() }
        await #expect(throws: (any Error).self) {
            try await EgressClient.run(
                options: .init(host: "timeout.example"), resolver: resolver,
                connectTimeout: .milliseconds(100), log: { _ in })
        }
    }

    @Test
    func preCancelledTaskDoesNotResolve() async throws {
        let resolver = ControlledResolver()
        defer { resolver.cancelQueries() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EgressClient.run(
                options: .init(host: "cancel.example"), resolver: resolver, log: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(resolver.queries.withLock { $0 } == 0)
    }

    @Test
    func invalidPolicyPrecedesDNSAndAdmission() async throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let file = try fixture.writeValidList()
        try FileManager.default.removeItem(at: file.appendingPathExtension("sha256"))
        let resolver = ControlledResolver()
        defer { resolver.cancelQueries() }
        let logs = Mutex(0)
        await #expect(throws: IPAdmissionPolicyFileLoadError.self) {
            try await EgressClient.run(
                options: .init(host: "never-resolve.example", allowFile: file), resolver: resolver,
                log: { _ in logs.withLock { $0 += 1 } })
        }
        #expect(resolver.queries.withLock { $0 } == 0)
        #expect(logs.withLock { $0 } == 0)
    }
}
