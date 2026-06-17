#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
#
# This source file is part of the swift-cidr-admission project.
#
# Copyright (c) 2026 Craig A. Munro
#
# Licensed under the Apache License, Version 2.0.
# See the LICENSE file for details.
#
# SPDX-License-Identifier: Apache-2.0
#
#===----------------------------------------------------------------------===#

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BENCHMARK_PACKAGE_ROOT="${PACKAGE_ROOT}/Benchmarks"
TARGET="${CIDR_ADMISSION_BENCHMARK_TARGET:-CIDRAdmissionBenchmarkTarget}"

usage() {
    cat <<EOF
Usage: ./scripts/benchmarks.sh <command> [swift-package-benchmark args...]

Commands:
  build    Build the benchmark target in release mode
  list     List discovered benchmarks
  run      Run the benchmark suite
  help     Show this help text

Examples:
  ./scripts/benchmarks.sh build
  ./scripts/benchmarks.sh list
  ./scripts/benchmarks.sh run --filter '^policy\\.lookup\\.v4\\.combined\\.denyMissAllowLast\\.500$'
EOF
}

if [[ ! -f "${BENCHMARK_PACKAGE_ROOT}/Package.swift" ]]; then
    echo "error: could not find Benchmarks/Package.swift at ${BENCHMARK_PACKAGE_ROOT}" >&2
    exit 1
fi

command="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "${command}" in
build)
    exec swift build -c release --package-path "${BENCHMARK_PACKAGE_ROOT}" --target "${TARGET}" "$@"
    ;;
list)
    exec swift package --package-path "${BENCHMARK_PACKAGE_ROOT}" benchmark list "$@"
    ;;
run)
    exec swift package --package-path "${BENCHMARK_PACKAGE_ROOT}" benchmark --target "${TARGET}" "$@"
    ;;
help | -h | --help)
    usage
    ;;
*)
    echo "error: unknown command '${command}'" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
