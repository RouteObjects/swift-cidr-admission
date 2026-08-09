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

import Benchmark
import CIDR
import CIDRAdmission

private struct PolicyFamilyFixture {
    let name: String
    let missAddress: AnyIPAddress
    let allowNetworkStrings: [String]
    let denyNetworkStrings: [String]
    let allowNetworks: [AnyIPNetwork]
    let denyNetworks: [AnyIPNetwork]
    let allowAddresses: [AnyIPAddress]
    let denyAddresses: [AnyIPAddress]
}

private let policySizes = [0, 1, 10, 50, 100, 250, 500, 1_000, 10_000]
private let filePolicySizes = [500, 1_000, 10_000]
private let maximumPolicySize = policySizes.max() ?? 0

@MainActor
let benchmarks = {
    let metrics: [BenchmarkMetric] = [
        .throughput,
        .wallClock,
        .mallocCountSmall,
        .mallocCountLarge,
        .mallocCountTotal,
        .objectAllocCount,
        .retainCount,
        .releaseCount,
        .retainReleaseDelta,
    ]

    func lookupConfiguration() -> Benchmark.Configuration {
        .init(
            metrics: metrics,
            warmupIterations: 3,
            // CHANGE: Gapped 10k-rule indexes make a million-call batch exceed the complete
            // sampling window; one thousand calls retains amortization and yields many samples.
            scalingFactor: .kilo,
            maxDuration: .seconds(2)
        )
    }

    func decisionConfiguration() -> Benchmark.Configuration {
        .init(
            metrics: metrics,
            warmupIterations: 3,
            // CHANGE: Detailed scans scale with rule count; one million calls makes a 10k-rule
            // sample indivisible for tens of seconds and defeats maxDuration.
            scalingFactor: .kilo,
            maxDuration: .seconds(2)
        )
    }

    func compileConfiguration(size: Int) -> Benchmark.Configuration {
        .init(
            metrics: metrics,
            warmupIterations: 2,
            // CHANGE: Let maxDuration control large construction cases between single-policy
            // samples instead of forcing one thousand 10k-rule policies per sample.
            scalingFactor: size >= 1_000 ? .one : .kilo,
            maxDuration: .seconds(2)
        )
    }

    func fileLoadConfiguration() -> Benchmark.Configuration {
        .init(
            metrics: metrics,
            warmupIterations: 1,
            scalingFactor: .one,
            maxDuration: .seconds(2)
        )
    }

    func makePolicy(
        allow: ArraySlice<AnyIPNetwork> = [],
        deny: ArraySlice<AnyIPNetwork> = []
    ) -> IPAdmissionPolicy {
        IPAdmissionPolicy(
            allow: Array(allow),
            deny: Array(deny),
            defaultAction: .deny
        )
    }

    func makeConfiguration(
        allow: ArraySlice<String> = [],
        deny: ArraySlice<String> = []
    ) -> IPAdmissionPolicyConfiguration {
        IPAdmissionPolicyConfiguration(
            defaultAction: .deny,
            allow: Array(allow),
            deny: Array(deny)
        )
    }

    func registerLookupBenchmarks(for fixture: PolicyFamilyFixture) {
        let emptyPolicy = IPAdmissionPolicy(defaultAction: .deny)

        Benchmark(
            "policy.lookup.\(fixture.name).empty.defaultDeny",
            configuration: lookupConfiguration()
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(emptyPolicy.allows(fixture.missAddress))
            }
        }

        for size in policySizes where size > 0 {
            let allowOnlyPolicy = makePolicy(allow: fixture.allowNetworks.prefix(size))
            let denyOnlyPolicy = makePolicy(deny: fixture.denyNetworks.prefix(size))
            let combinedPolicy = makePolicy(
                allow: fixture.allowNetworks.prefix(size),
                deny: fixture.denyNetworks.prefix(size)
            )
            let firstAllowAddress = fixture.allowAddresses[0]
            let lastAllowAddress = fixture.allowAddresses[size - 1]
            let lastDenyAddress = fixture.denyAddresses[size - 1]

            Benchmark(
                "policy.lookup.\(fixture.name).allowOnly.hit.first.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(allowOnlyPolicy.allows(firstAllowAddress))
                }
            }

            Benchmark(
                "policy.lookup.\(fixture.name).allowOnly.hit.last.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(allowOnlyPolicy.allows(lastAllowAddress))
                }
            }

            Benchmark(
                "policy.lookup.\(fixture.name).allowOnly.miss.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(allowOnlyPolicy.allows(fixture.missAddress))
                }
            }

            Benchmark(
                "policy.lookup.\(fixture.name).denyOnly.hit.last.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(denyOnlyPolicy.allows(lastDenyAddress))
                }
            }

            Benchmark(
                "policy.lookup.\(fixture.name).denyOnly.miss.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(denyOnlyPolicy.allows(fixture.missAddress))
                }
            }

            Benchmark(
                "policy.lookup.\(fixture.name).combined.denyMissAllowLast.\(size)",
                configuration: lookupConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(combinedPolicy.allows(lastAllowAddress))
                }
            }

            Benchmark(
                "policy.decision.\(fixture.name).combined.denyMissAllowLast.\(size)",
                configuration: decisionConfiguration()
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(combinedPolicy.decision(for: lastAllowAddress).isAllowed)
                }
            }
        }
    }

    func registerCompileBenchmarks(for fixture: PolicyFamilyFixture) {
        for size in policySizes {
            let allowOnlyConfiguration = makeConfiguration(
                allow: fixture.allowNetworkStrings.prefix(size)
            )
            let combinedConfiguration = makeConfiguration(
                allow: fixture.allowNetworkStrings.prefix(size),
                deny: fixture.denyNetworkStrings.prefix(size)
            )

            Benchmark(
                "policy.compile.\(fixture.name).allowOnly.\(size)",
                configuration: compileConfiguration(size: size)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    let policy = try! IPAdmissionPolicy(configuration: allowOnlyConfiguration)
                    blackHole(policy.allow.count)
                }
            }

            Benchmark(
                "policy.compile.\(fixture.name).combined.\(size)",
                configuration: compileConfiguration(size: size)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    let policy = try! IPAdmissionPolicy(configuration: combinedConfiguration)
                    blackHole(policy.deny.count + policy.allow.count)
                }
            }
        }
    }

    for fixture in makeFixtures(maximumCount: maximumPolicySize) {
        registerLookupBenchmarks(for: fixture)
        registerCompileBenchmarks(for: fixture)
    }

    // CHANGE: File-backed measurements use stable artifacts to compare
    // parsing/index construction with and without required checksum verification.
    let fileFixtureStore = try! FilePolicyBenchmarkFixtureStore(
        sizes: filePolicySizes
    )
    for fixture in fileFixtureStore.fixtures {
        Benchmark(
            "policy.load.\(fixture.family).\(fixture.representation).verifyIfPresent.\(fixture.ruleCount)",
            configuration: fileLoadConfiguration()
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try! fixture.load(checksumPolicy: .verifyIfPresent).allow.count)
            }
        }

        Benchmark(
            "policy.load.\(fixture.family).\(fixture.representation).required.\(fixture.ruleCount)",
            configuration: fileLoadConfiguration()
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try! fixture.load(checksumPolicy: .required).allow.count)
            }
        }
    }
}

private func makeFixtures(maximumCount: Int) -> [PolicyFamilyFixture] {
    [
        makeIPv4Fixture(maximumCount: maximumCount),
        makeIPv6Fixture(maximumCount: maximumCount),
    ]
}

private func makeIPv4Fixture(maximumCount: Int) -> PolicyFamilyFixture {
    let allowNetworkStrings = (0..<maximumCount).map { index in
        let slot = index * 2
        return "10.\(slot / 256).\(slot % 256).0/24"
    }
    let denyNetworkStrings = (0..<maximumCount).map { index in
        let slot = index * 2
        return "172.\(16 + slot / 256).\(slot % 256).0/24"
    }
    let allowAddresses = (0..<maximumCount).map { index in
        let slot = index * 2
        return AnyIPAddress("10.\(slot / 256).\(slot % 256).1")!
    }
    let denyAddresses = (0..<maximumCount).map { index in
        let slot = index * 2
        return AnyIPAddress("172.\(16 + slot / 256).\(slot % 256).1")!
    }

    return PolicyFamilyFixture(
        name: "v4",
        missAddress: AnyIPAddress("198.51.100.1")!,
        allowNetworkStrings: allowNetworkStrings,
        denyNetworkStrings: denyNetworkStrings,
        allowNetworks: allowNetworkStrings.map { AnyIPNetwork($0)! },
        denyNetworks: denyNetworkStrings.map { AnyIPNetwork($0)! },
        allowAddresses: allowAddresses,
        denyAddresses: denyAddresses
    )
}

private func makeIPv6Fixture(maximumCount: Int) -> PolicyFamilyFixture {
    let allowNetworkStrings = (0..<maximumCount).map { index in
        "2001:db8:\(String(index * 2, radix: 16))::/48"
    }
    let denyNetworkStrings = (0..<maximumCount).map { index in
        "2001:db8:\(String(0x8000 + index * 2, radix: 16))::/48"
    }
    let allowAddresses = (0..<maximumCount).map { index in
        AnyIPAddress("2001:db8:\(String(index * 2, radix: 16))::1")!
    }
    let denyAddresses = (0..<maximumCount).map { index in
        AnyIPAddress("2001:db8:\(String(0x8000 + index * 2, radix: 16))::1")!
    }

    return PolicyFamilyFixture(
        name: "v6",
        missAddress: AnyIPAddress("2001:db8:ffff::1")!,
        allowNetworkStrings: allowNetworkStrings,
        denyNetworkStrings: denyNetworkStrings,
        allowNetworks: allowNetworkStrings.map { AnyIPNetwork($0)! },
        denyNetworks: denyNetworkStrings.map { AnyIPNetwork($0)! },
        allowAddresses: allowAddresses,
        denyAddresses: denyAddresses
    )
}
