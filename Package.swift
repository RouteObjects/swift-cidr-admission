// swift-tools-version: 6.1

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

import PackageDescription

let package = Package(
    name: "swift-cidr-admission",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CIDRAdmission", targets: ["CIDRAdmission"]),
    ],
    dependencies: [
        .package(name: "swift-cidr", path: "../Example Framework/Packages/swift-cidr"),
        // CHANGE: SwiftNIO is only needed by the executable example; the library target stays framework-neutral.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
    ],
    targets: [
        .target(
            name: "CIDRAdmission",
            dependencies: [
                .product(name: "CIDR", package: "swift-cidr"),
            ]
        ),
        .testTarget(
            name: "CIDRAdmissionTests",
            dependencies: [
                .product(name: "CIDR", package: "swift-cidr"),
                "CIDRAdmission",
            ]
        ),
        .executableTarget(
            name: "NIOTCPEchoAdmissionServer",
            dependencies: [
                "CIDRAdmission",
                .product(name: "CIDR", package: "swift-cidr"),
                .product(name: "CIDRNIO", package: "swift-cidr"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
