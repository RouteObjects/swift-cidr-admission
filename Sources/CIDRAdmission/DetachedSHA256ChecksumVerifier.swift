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

import Crypto
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Verifies the exact detached SHA-256 format emitted by cidrmerge.
enum DetachedSHA256ChecksumVerifier {
    static func verify(
        sourceData: Data,
        sourcePath: String,
        sourceBasename: String,
        checksumData: Data,
        checksumPath: String,
        ruleSet: AdmissionRuleSet
    ) throws {
        let bytes = [UInt8](checksumData)
        guard bytes.count >= 67,
            bytes[64] == 0x20,
            bytes[65] == 0x20,
            bytes.last == 0x0A,
            bytes[..<64].allSatisfy(isLowercaseHexadecimal)
        else {
            throw IPAdmissionPolicyFileLoadError.checksumMalformed(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: checksumPath
            )
        }

        let filenameBytes = Array(bytes[66..<(bytes.count - 1)])
        guard !filenameBytes.isEmpty,
            !filenameBytes.contains(0x0A),
            !filenameBytes.contains(0x0D),
            let checksumBasename = String(bytes: filenameBytes, encoding: .utf8)
        else {
            throw IPAdmissionPolicyFileLoadError.checksumMalformed(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: checksumPath
            )
        }

        // Compare UTF-8 bytes rather than canonically-equivalent Swift Strings. The
        // detached record names one exact filesystem artifact, including Unicode normalization.
        guard filenameBytes == Array(sourceBasename.utf8) else {
            throw IPAdmissionPolicyFileLoadError.checksumFilenameMismatch(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: checksumPath,
                expected: sourceBasename,
                actual: checksumBasename
            )
        }

        let expectedDigest = String(decoding: bytes[..<64], as: UTF8.self)
        let actualDigest = hexadecimalDigest(of: sourceData)
        guard expectedDigest == actualDigest else {
            throw IPAdmissionPolicyFileLoadError.checksumDigestMismatch(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: checksumPath,
                expected: expectedDigest,
                actual: actualDigest
            )
        }
    }

    private static func isLowercaseHexadecimal(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
    }

    private static func hexadecimalDigest(of data: Data) -> String {
        let hexadecimalDigits: [UInt8] = Array("0123456789abcdef".utf8)
        let digest = SHA256.hash(data: data)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(hexadecimalDigits[Int(byte >> 4)])
            bytes.append(hexadecimalDigits[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// The local-file operations used by the synchronous role loader.
struct IPAdmissionPolicyFileAccess: Sendable {
    enum ReadResult: Sendable, Equatable {
        case missing
        case notRegularFile
        case data(Data)
    }

    static let live = Self(
        openAndRead: { url in try openAndReadRegularFile(url) }
    )

    let openAndRead: @Sendable (URL) throws -> ReadResult

    private static func openAndReadRegularFile(_ url: URL) throws -> ReadResult {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw POSIXFileAccessError(operation: "encode path", errorNumber: EINVAL)
            }

            // O_NONBLOCK makes FIFO/device preflight non-blocking. The descriptor is then
            // pinned across fstat and every read, eliminating path inspection/read replacement.
            let descriptor = systemOpen(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else {
                let errorNumber = currentErrno
                if errorNumber == ENOENT || errorNumber == ENOTDIR {
                    return .missing
                }
                throw POSIXFileAccessError(operation: "open", errorNumber: errorNumber)
            }
            defer { _ = systemClose(descriptor) }

            var status = stat()
            guard systemFileStatus(descriptor, &status) == 0 else {
                throw POSIXFileAccessError(operation: "fstat", errorNumber: currentErrno)
            }
            guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                return .notRegularFile
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                    guard let baseAddress = bytes.baseAddress else { return 0 }
                    return systemRead(descriptor, baseAddress, bytes.count)
                }
                if count > 0 {
                    data.append(contentsOf: buffer[..<count])
                    continue
                }
                if count == 0 {
                    return .data(data)
                }

                let errorNumber = currentErrno
                if errorNumber == EINTR {
                    continue
                }
                throw POSIXFileAccessError(operation: "read", errorNumber: errorNumber)
            }
        }
    }

    private static func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
        #if canImport(Darwin)
            Darwin.open(path, flags)
        #elseif canImport(Glibc)
            Glibc.open(path, flags)
        #endif
    }

    private static func systemFileStatus(_ descriptor: Int32, _ status: UnsafeMutablePointer<stat>)
        -> Int32
    {
        #if canImport(Darwin)
            Darwin.fstat(descriptor, status)
        #elseif canImport(Glibc)
            Glibc.fstat(descriptor, status)
        #endif
    }

    private static func systemRead(
        _ descriptor: Int32,
        _ buffer: UnsafeMutableRawPointer,
        _ count: Int
    ) -> Int {
        #if canImport(Darwin)
            Darwin.read(descriptor, buffer, count)
        #elseif canImport(Glibc)
            Glibc.read(descriptor, buffer, count)
        #endif
    }

    private static func systemClose(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
            Darwin.close(descriptor)
        #elseif canImport(Glibc)
            Glibc.close(descriptor)
        #endif
    }

    private static var currentErrno: Int32 {
        #if canImport(Darwin)
            Darwin.errno
        #elseif canImport(Glibc)
            Glibc.errno
        #endif
    }
}

private struct POSIXFileAccessError: Error, Sendable, LocalizedError {
    let operation: String
    let errorNumber: Int32

    var errorDescription: String? {
        "\(operation) failed: \(String(cString: strerror(errorNumber))) (POSIX error \(errorNumber))"
    }
}

/// Loads one optional allow or deny role, validating any required or present checksum before parsing.
struct IPAdmissionPolicyRoleLoader: Sendable {
    static let live = Self(fileAccess: .live)

    let fileAccess: IPAdmissionPolicyFileAccess

    func load(
        file: URL?,
        ruleSet: AdmissionRuleSet,
        checksumPolicy: IPAdmissionChecksumPolicy
    ) throws -> [AdmissionRule] {
        guard let file else { return [] }
        guard file.isFileURL, isLocalFileURL(file) else {
            throw IPAdmissionPolicyFileLoadError.unsupportedURL(
                ruleSet: ruleSet,
                url: file.absoluteString
            )
        }

        let sourcePath = file.path
        let sourceData = try readSource(file, ruleSet: ruleSet, path: sourcePath)
        let checksumURL = URL(fileURLWithPath: sourcePath + ".sha256")

        if let checksumData = try readChecksum(
            checksumURL,
            sourcePath: sourcePath,
            ruleSet: ruleSet,
            policy: checksumPolicy
        ) {
            // CMatch the supplied digest against the single buffered source read before
            // parsing, without implying that an unkeyed digest authenticates the source.
            try DetachedSHA256ChecksumVerifier.verify(
                sourceData: sourceData,
                sourcePath: sourcePath,
                sourceBasename: file.lastPathComponent,
                checksumData: checksumData,
                checksumPath: checksumURL.path,
                ruleSet: ruleSet
            )
        }

        return try IPListTextParser.parse(sourceData, ruleSet: ruleSet, path: sourcePath)
    }

    private func readSource(
        _ url: URL,
        ruleSet: AdmissionRuleSet,
        path: String
    ) throws -> Data {
        let result: IPAdmissionPolicyFileAccess.ReadResult
        do {
            result = try fileAccess.openAndRead(url)
        } catch {
            throw IPAdmissionPolicyFileLoadError.unreadableFile(
                ruleSet: ruleSet,
                path: path,
                reason: error.localizedDescription
            )
        }

        switch result {
        case .missing:
            throw IPAdmissionPolicyFileLoadError.fileNotFound(ruleSet: ruleSet, path: path)
        case .notRegularFile:
            throw IPAdmissionPolicyFileLoadError.notRegularFile(ruleSet: ruleSet, path: path)
        case .data(let data):
            return data
        }
    }

    private func readChecksum(
        _ url: URL,
        sourcePath: String,
        ruleSet: AdmissionRuleSet,
        policy: IPAdmissionChecksumPolicy
    ) throws -> Data? {
        let result: IPAdmissionPolicyFileAccess.ReadResult
        do {
            result = try fileAccess.openAndRead(url)
        } catch {
            throw IPAdmissionPolicyFileLoadError.checksumUnreadable(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: url.path,
                reason: error.localizedDescription
            )
        }

        switch result {
        case .missing where policy == .verifyIfPresent:
            return nil
        case .missing:
            throw IPAdmissionPolicyFileLoadError.checksumNotFound(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: url.path
            )
        case .notRegularFile:
            throw IPAdmissionPolicyFileLoadError.checksumNotRegularFile(
                ruleSet: ruleSet,
                path: sourcePath,
                checksumPath: url.path
            )
        case .data(let data):
            return data
        }
    }

    private func isLocalFileURL(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        return host.isEmpty || isASCIICaseInsensitiveLocalhost(host)
    }

    private func isASCIICaseInsensitiveLocalhost(_ host: String) -> Bool {
        let expected = Array("localhost".utf8)
        let actual = Array(host.utf8)
        guard actual.count == expected.count else { return false }

        return zip(actual, expected).allSatisfy { byte, expectedByte in
            let lowercaseByte = (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
            return lowercaseByte == expectedByte
        }
    }
}
