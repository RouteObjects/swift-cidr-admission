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

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
VERSION="${1:-}"
CIDRMERGE_PACKAGE="${CIDRMERGE_PACKAGE:-${PACKAGE_ROOT}/../cidrmerge}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "${VERSION}" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] ||
    fail "Usage: scripts/check-release.sh MAJOR.MINOR.PATCH"

cd "${PACKAGE_ROOT}"

[[ -z "$(git status --short)" ]] ||
    fail "Commit or stash package changes before running the release check."

release_temporary_directory="$(
    mktemp -d "${TMPDIR:-/tmp}/cidr-admission-release-check.XXXXXX"
)"
cleanup() {
    rm -rf -- "${release_temporary_directory}"
}
trap cleanup EXIT

release_notes="Documentation/ReleaseNotes/${VERSION}.md"
for required in \
    LICENSE \
    README.md \
    RELEASING.md \
    Package.swift \
    Package.resolved \
    .spi.yml \
    .github/workflows/ci.yml \
    .github/workflows/release.yml \
    "${release_notes}" \
    scripts/check-cidrmerge-pipeline.sh \
    scripts/check-consumers.sh; do
    [[ -f "${required}" ]] || fail "Required release file is missing: ${required}"
done
[[ -f "${CIDRMERGE_PACKAGE}/Package.swift" ]] ||
    fail "cidrmerge package not found at ${CIDRMERGE_PACKAGE}"

[[ "$(sed -n '1p' "${release_notes}")" == "# swift-cidr-admission ${VERSION}" ]] ||
    fail "Release notes must begin with '# swift-cidr-admission ${VERSION}'."

grep -Fq 'Apache License' LICENSE || fail "LICENSE is not the Apache License."
while IFS= read -r swift_file; do
    grep -Fq 'SPDX-License-Identifier: Apache-2.0' "${swift_file}" ||
        fail "Apache license header is missing: ${swift_file}"
done < <(git ls-files -- '*.swift')
while IFS= read -r shell_file; do
    grep -Fq 'SPDX-License-Identifier: Apache-2.0' "${shell_file}" ||
        fail "Apache license header is missing: ${shell_file}"
done < <(git ls-files -- 'scripts/*.sh')

# Assemble sensitive markers from fragments so this gate cannot match its own source.
mac_home="/""Users/"
linux_home="/""home/[^/]+/"
private_var="/""private/var/"
private_key="-----BE""GIN (OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----"
aws_key="(A""KIA|A""SIA)[0-9A-Z]{16}"
github_token="gh""[pousr]_[A-Za-z0-9]{20,}"
github_pat="github""_pat_[A-Za-z0-9_]{20,}"
slack_token="xo""x[baprs]-[A-Za-z0-9-]{20,}"
api_key="sk""-(live|proj)-[A-Za-z0-9_-]{16,}"

if git grep --quiet -I -E \
    -e "${mac_home}" \
    -e "${linux_home}" \
    -e "${private_var}" \
    -- .; then
    fail "Tracked files contain a private absolute path."
else
    status=$?
    [[ ${status} -eq 1 ]] || fail "Unable to audit tracked private paths."
fi
if git grep --quiet -I -E \
    -e "${private_key}" \
    -e "${aws_key}" \
    -e "${github_token}" \
    -e "${github_pat}" \
    -e "${slack_token}" \
    -e "${api_key}" \
    -- .; then
    fail "Tracked files contain a credential or private-key marker."
else
    status=$?
    [[ ${status} -eq 1 ]] || fail "Unable to audit tracked sensitive markers."
fi

# Public consumers must resolve the release through canonical HTTPS dependencies.
expected_direct_dependencies=$'https://github.com/RouteObjects/swift-cidr.git\nhttps://github.com/apple/swift-crypto.git'
actual_direct_dependencies="$(
    sed -nE 's/.*url:[[:space:]]*"([^"]+)".*/\1/p' Package.swift | LC_ALL=C sort
)"
[[ "${actual_direct_dependencies}" == "${expected_direct_dependencies}" ]] ||
    fail "Package.swift contains an unexpected direct dependency URL."
if grep -Eq 'git@|file:///|[.]package[[:space:]]*[(][[:space:]]*path[[:space:]]*:' \
    Package.swift Package.resolved; then
    fail "The public package dependency graph contains a local or credential-bound source."
fi

git diff --check

root_lock_snapshot="${release_temporary_directory}/Package.resolved"
pipeline_lock_snapshot="${release_temporary_directory}/CIDRMergePipeline.Package.resolved"
cp Package.resolved "${root_lock_snapshot}"
cp IntegrationTests/CIDRMergePipeline/Package.resolved "${pipeline_lock_snapshot}"
swift package resolve
swift package --package-path IntegrationTests/CIDRMergePipeline resolve
cmp "${root_lock_snapshot}" Package.resolved || fail "Root dependency lock changed."
cmp "${pipeline_lock_snapshot}" IntegrationTests/CIDRMergePipeline/Package.resolved ||
    fail "cidrmerge pipeline dependency lock changed."

swift build
swift test
swift build -c release
swift test -c release

CIDRMERGE_PACKAGE="${CIDRMERGE_PACKAGE}" "${SCRIPT_DIR}/check-cidrmerge-pipeline.sh"
swift build --package-path Examples/NIOTCPEchoAdmissionServer

# CHANGE: Benchmark 1.35 exposes different dependency manifests to Swift 6.1 and 6.3.
# Build a tracked snapshot so Swift 6.1 can normalize its nested lock without changing
# the canonical Swift 6.3 lock in the reviewed release checkout.
benchmark_package_root="${release_temporary_directory}/benchmark-package"
mkdir -p "${benchmark_package_root}"
git archive --format=tar HEAD | tar -xf - -C "${benchmark_package_root}"
BENCHMARK_DISABLE_MALLOC_INTERPOSER=1 \
    BENCHMARK_DISABLE_JEMALLOC=1 \
    swift build \
        --package-path "${benchmark_package_root}/Benchmarks" \
        -c release \
        --target CIDRAdmissionBenchmarkTarget

symbol_graph_directory="${release_temporary_directory}/symbol-graphs"
mkdir -p "${symbol_graph_directory}"
# Validate the public surface SPI will extract without adding a DocC plugin dependency.
swift build \
    --target CIDRAdmission \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "${symbol_graph_directory}" \
    -Xswiftc -symbol-graph-minimum-access-level \
    -Xswiftc public
symbol_graph="${symbol_graph_directory}/CIDRAdmission.symbols.json"
[[ -s "${symbol_graph}" ]] || fail "CIDRAdmission public symbol graph is missing."
for public_symbol in \
    CIDRAdmission \
    IPAdmissionPolicy \
    AdmissionRule \
    AdmissionDecisionReason \
    IPAdmissionPolicyConfiguration \
    IPAdmissionPolicyFileConfiguration \
    IPAdmissionChecksumPolicy \
    IPAdmissionPolicyRuleTextError \
    IPAdmissionPolicyFileLoadError; do
    grep -Eq "\"(name|title)\"[[:space:]]*:[[:space:]]*\"${public_symbol}\"" \
        "${symbol_graph}" || fail "Public symbol graph is missing ${public_symbol}."
done
grep -Eq '"title"[[:space:]]*:[[:space:]]*"init\(allow:deny:defaultAction:\)"' \
    "${symbol_graph}" || fail "Public symbol graph is missing the legacy network initializer."
grep -Eq '"title"[[:space:]]*:[[:space:]]*"init\(allowRules:denyRules:defaultAction:\)"' \
    "${symbol_graph}" || fail "Public symbol graph is missing the programmatic rule initializer."
grep -Eq '"title"[[:space:]]*:[[:space:]]*"init\(fileConfiguration:\)"' \
    "${symbol_graph}" || fail "Public symbol graph is missing the file-policy initializer."
for private_symbol in \
    DetachedSHA256ChecksumVerifier \
    IPAdmissionCoverageIndex \
    IPAdmissionPolicyRoleLoader \
    IPListTextParser; do
    if grep -Eq "\"title\"[[:space:]]*:[[:space:]]*\"${private_symbol}\"" \
        "${symbol_graph}"; then
        fail "Private implementation type leaked into the public symbol graph: ${private_symbol}."
    fi
done

"${SCRIPT_DIR}/check-consumers.sh"

case "$(uname -s)" in
Darwin)
    # Compile the public library at its declared iOS floor when an Apple SDK is available.
    ios_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    swift build \
        --target CIDRAdmission \
        --triple arm64-apple-ios18.0-simulator \
        --sdk "${ios_sdk}"
    ;;
Linux)
    ;;
*)
    fail "Unsupported release-check host: $(uname -s)"
    ;;
esac

git diff --check
final_status="$(git status --short)"
if [[ -n "${final_status}" ]]; then
    printf '%s\n' "${final_status}" >&2
    fail "Release checks changed the working tree."
fi

printf 'swift-cidr-admission %s release checks passed.\n' "${VERSION}"
