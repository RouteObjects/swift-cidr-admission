// swift-tools-version: 6.3

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
    name: "swift-cidr-admission-benchmarks",
    platforms: [
        // Benchmark executables are a macOS/Linux command-line workflow. iOS is declared so
        // SwiftPM/Xcode resolve this nested package with the same Apple platform floor as CIDRAdmission.
        .iOS(.v18),
        .macOS(.v15),
    ],
    dependencies: [
        // CHANGE: Swift 6.3 selects Benchmark's manifest with a compatible ArgumentParser range.
        .package(name: "swift-cidr-admission", path: ".."),
        .package(
            url: "https://github.com/RouteObjects/swift-cidr.git",
            .upToNextMinor(from: "0.8.0")
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            .upToNextMajor(from: "5.0.3")
        ),
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.35.0"),
    ],
    targets: [
        .executableTarget(
            name: "CIDRAdmissionBenchmarkTarget",
            dependencies: [
                .product(name: "CIDRAdmission", package: "swift-cidr-admission"),
                .product(name: "CIDR", package: "swift-cidr"),
                // CHANGE: Benchmark-only fixture generation writes valid detached checksums.
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "CIDRAdmissionBenchmarkTarget",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    ]
)
