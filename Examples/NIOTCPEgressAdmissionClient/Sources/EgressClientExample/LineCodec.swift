//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// The framing pattern adapts SwiftNIO's NIOTCPEchoServer sample.
// Copyright (c) 2026 Craig A. Munro
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// See SwiftNIO's LICENSE.txt and CONTRIBUTORS.txt for upstream attribution.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIOCore

struct LineCodec: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = String
    typealias OutboundIn = String
    static let maximumLength = 64 * 1024

    static func validate(_ message: String) throws {
        guard message.utf8.count <= maximumLength else { throw ClientError.frameTooLarge }
        guard !message.utf8.contains(10), !message.utf8.contains(13) else {
            throw ClientError.lineBreakInMessage
        }
    }

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws
        -> DecodingState
    {
        let bytes = buffer.readableBytesView
        guard let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else {
            guard bytes.count <= Self.maximumLength else { throw ClientError.frameTooLarge }
            return .needMoreData
        }
        let length = newline - buffer.readerIndex
        guard length <= Self.maximumLength else { throw ClientError.frameTooLarge }
        guard let message = String(bytes: bytes.prefix(length), encoding: .utf8) else {
            throw ClientError.invalidUTF8
        }
        try Self.validate(message)
        buffer.moveReaderIndex(forwardBy: length + 1)
        context.fireChannelRead(wrapInboundOut(message))
        return .continue
    }

    mutating func decodeLast(
        context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool
    )
        throws -> DecodingState
    {
        let state = try decode(context: context, buffer: &buffer)
        if state == .needMoreData && buffer.readableBytes > 0 { throw ClientError.prematureEOF }
        return state
    }

    func encode(data: String, out: inout ByteBuffer) throws {
        try Self.validate(data)
        out.writeString(data)
        out.writeInteger(UInt8(ascii: "\n"))
    }
}
