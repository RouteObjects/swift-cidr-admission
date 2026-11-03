// swift-tools-version: 6.2

//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Copyright (c) 2026 Craig A. Munro
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-cidr-admission-nio-egress-example",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        .package(name: "swift-cidr-admission", path: "../.."),
        .package(
            url: "https://github.com/RouteObjects/swift-cidr.git", .upToNextMinor(from: "0.8.1")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
    ],
    targets: [
        .executableTarget(
            name: "NIOTCPEgressAdmissionClient",
            dependencies: ["EgressClientExample"]
        ),
        // Keep the executable entry point out of optimized Swift Testing bundles.
        // This internal target is not exposed as a library product.
        .target(
            name: "EgressClientExample",
            dependencies: [
                .product(name: "CIDRAdmission", package: "swift-cidr-admission"),
                .product(name: "CIDR", package: "swift-cidr"),
                .product(name: "CIDRNIO", package: "swift-cidr"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            // Preserve the exact bytes covered by the detached checksum.
            resources: [.copy("Resources/Policy")]
        ),
        .testTarget(
            name: "NIOTCPEgressAdmissionClientTests",
            dependencies: [
                "EgressClientExample",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ]
)
