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
        .library(name: "CIDRAdmission", targets: ["CIDRAdmission"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/RouteObjects/swift-cidr.git",
            .upToNextMinor(from: "0.5.0")
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            .upToNextMajor(from: "4.5.1")
        ),
    ],
    targets: [
        .target(
            name: "CIDRAdmission",
            dependencies: [
                .product(name: "CIDR", package: "swift-cidr"),
                // File-backed policy verifies exact deployed bytes before parsing them.
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "CIDRAdmissionTests",
            dependencies: [
                .product(name: "CIDR", package: "swift-cidr"),
                "CIDRAdmission",
            ]
        ),
    ]
)
