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
import CIDRNIO
import NIOCore

final class EgressAdmissionHandler: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer

    private let policy: IPAdmissionPolicy
    private let log: @Sendable (String) -> Void

    init(policy: IPAdmissionPolicy, log: @escaping @Sendable (String) -> Void) {
        self.policy = policy
        self.log = log
    }

    func connect(
        context: ChannelHandlerContext, to destination: SocketAddress,
        promise: EventLoopPromise<Void>?
    ) {
        do {
            // Integration point 3: Inspect this attempt's destination, not remoteAddress after connecting.
            let address = try AnyIPAddress(socketAddress: destination)
            // Integration point 4: Reuse the direction-neutral policy for the destination IP.
            let decision = policy.decision(for: address)
            guard decision.isAllowed else {
                throw EgressAdmissionError.denied(
                    destination: destination.description, decision: decision)
            }
            log("Allowed destination \(destination): \(decision.logDescription)")
            // Integration point 5: Only allowed destinations reach the underlying socket connect.
            context.connect(to: destination, promise: promise)
        } catch {
            log("Denied destination \(destination): \(error)")
            promise?.fail(error)
            context.close(promise: nil)
        }
    }
}

enum EgressAdmissionError: Error, Sendable, CustomStringConvertible {
    case denied(destination: String, decision: AdmissionDecision)

    var description: String {
        switch self {
        case .denied(let destination, let decision):
            "Connection to \(destination) rejected: \(decision.logDescription)"
        }
    }
}

extension AdmissionDecision {
    fileprivate var logDescription: String {
        switch reason {
        case .matched(let ruleSet, let rule): "\(action) via \(ruleSet) rule \(rule)"
        case .defaultAction: "\(action) via default action"
        }
    }
}
