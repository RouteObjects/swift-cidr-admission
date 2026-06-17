// swift-tools-version: 6.1

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
    ]
)
