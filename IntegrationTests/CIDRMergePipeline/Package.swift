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
    name: "CIDRMergePipelineAcceptance",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "CIDRMergePipelineAcceptance",
            targets: ["CIDRMergePipelineAcceptance"]
        )
    ],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/RouteObjects/swift-cidr.git",
            .upToNextMinor(from: "0.5.0")
        ),
    ],
    targets: [
        .executableTarget(
            name: "CIDRMergePipelineAcceptance",
            dependencies: [
                .product(name: "CIDRAdmission", package: "swift-cidr-admission"),
                .product(name: "CIDR", package: "swift-cidr"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
