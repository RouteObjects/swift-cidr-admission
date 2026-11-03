//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cidr-admission project.
// Copyright (c) 2026 Craig A. Munro
// Licensed under the Apache License, Version 2.0.
// See the LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import EgressClientExample

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@main
struct Client {
    static func main() async {
        let status = await ClientCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
        if status != 0 { exit(status) }
    }
}
