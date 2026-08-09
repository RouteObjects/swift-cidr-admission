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
PACKAGE_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
ACCEPTANCE_ROOT="${PACKAGE_ROOT}/IntegrationTests/CIDRMergePipeline"
CIDRMERGE_PACKAGE="${CIDRMERGE_PACKAGE:-${PACKAGE_ROOT}/../cidrmerge}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

repository_revision() {
    local repository="$1"
    local revision
    local status
    revision="$(git -C "${repository}" rev-parse HEAD)" || return 1
    status="$(git -C "${repository}" status --porcelain --untracked-files=normal -- \
        . ':(exclude)cidrmerge-pipeline')" || return 1
    if [[ -n "${status}" ]]; then
        revision="${revision}-dirty"
    fi
    printf '%s' "${revision}"
}

[[ -f "${CIDRMERGE_PACKAGE}/Package.swift" ]] ||
    fail "cidrmerge package not found at ${CIDRMERGE_PACKAGE}"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/cidrmerge-admission.XXXXXX")"
cleanup() {
    rm -rf -- "${temporary_directory}"
}
trap cleanup EXIT

swift build -c release --package-path "${CIDRMERGE_PACKAGE}" --product cidrmerge
cidrmerge_binary="$(swift build -c release --package-path "${CIDRMERGE_PACKAGE}" --show-bin-path)/cidrmerge"
[[ -x "${cidrmerge_binary}" ]] || fail "cidrmerge executable was not built"

swift build -c release --package-path "${ACCEPTANCE_ROOT}" \
    --product CIDRMergePipelineAcceptance
acceptance_binary="$(swift build -c release --package-path "${ACCEPTANCE_ROOT}" --show-bin-path)/CIDRMergePipelineAcceptance"
[[ -x "${acceptance_binary}" ]] || fail "pipeline acceptance executable was not built"

allow_source="${temporary_directory}/allow-source.txt"
deny_source="${temporary_directory}/deny-source.txt"

# Exercise the producer's initial BOM, CRLF, comments, address, network, range,
# overlap, adjacency, normalization, and mixed-family input handling in one seam fixture.
printf '%b' '\357\273\277# Gate 7 allow fixture\r\n192.0.2.1\r\n192.0.2.2...192.0.2.6\r\n192.0.2.7/32\r\n192.0.2.4/31 # contained overlap\r\n192.0.2.250\r\n198.51.100.190/26\r\n198.51.100.160...198.51.100.191\r\n2001:db8::1\r\n2001:db8::2...2001:db8::6\r\n2001:db8::7/128\r\n2001:db8::4/126\r\n2001:db8:1::2/126\r\n2001:db8:abcd::42\r\n' >"${allow_source}"
printf '%b' '\357\273\277# Gate 7 deny fixture\r\n192.0.2.3\r\n192.0.2.4...192.0.2.5\r\n192.0.2.6/32\r\n192.0.2.4/31 # contained overlap\r\n203.0.113.65/30\r\n203.0.113.250\r\n2001:db8::3\r\n2001:db8::4...2001:db8::5\r\n2001:db8::6/128\r\n2001:db8::4/127\r\n2001:db8:eeee::42\r\n2001:db8:ffff::1/127\r\n' >"${deny_source}"

for representation in ranges cidr; do
    mkdir -p "${temporary_directory}/${representation}" "${temporary_directory}/repeat-${representation}"
    for role in allow deny; do
        source_variable="${role}_source"
        source_path="${!source_variable}"
        output="${temporary_directory}/${representation}/${role}.${representation}.txt"
        repeated_output="${temporary_directory}/repeat-${representation}/${role}.${representation}.txt"

        "${cidrmerge_binary}" --input-format text --raw \
            --representation "${representation}" --checksum \
            --output "${output}" "${source_path}"
        "${cidrmerge_binary}" --input-format text --raw \
            --representation "${representation}" --checksum \
            --output "${repeated_output}" "${source_path}"

        cmp "${output}" "${repeated_output}" ||
            fail "${role} ${representation} output is not deterministic"
        cmp "${output}.sha256" "${repeated_output}.sha256" ||
            fail "${role} ${representation} checksum is not deterministic"
        if command -v sha256sum >/dev/null 2>&1; then
            (cd "$(dirname -- "${output}")" && sha256sum --check "$(basename -- "${output}").sha256")
        else
            (cd "$(dirname -- "${output}")" && shasum -a 256 --check "$(basename -- "${output}").sha256")
        fi
    done
done

allow_ranges="${temporary_directory}/ranges/allow.ranges.txt"
deny_ranges="${temporary_directory}/ranges/deny.ranges.txt"
allow_cidr="${temporary_directory}/cidr/allow.cidr.txt"
deny_cidr="${temporary_directory}/cidr/deny.cidr.txt"

cmp "${allow_ranges}" <(printf '%s\n' \
    '192.0.2.1...192.0.2.7' \
    '192.0.2.250...192.0.2.250' \
    '198.51.100.128...198.51.100.191' \
    '2001:db8::1...2001:db8::7' \
    '2001:db8:1::...2001:db8:1::3' \
    '2001:db8:abcd::42...2001:db8:abcd::42') || fail "unexpected allow range bytes"
cmp "${deny_ranges}" <(printf '%s\n' \
    '192.0.2.3...192.0.2.6' \
    '203.0.113.64...203.0.113.67' \
    '203.0.113.250...203.0.113.250' \
    '2001:db8::3...2001:db8::6' \
    '2001:db8:eeee::42...2001:db8:eeee::42' \
    '2001:db8:ffff::...2001:db8:ffff::1') || fail "unexpected deny range bytes"
cmp "${allow_cidr}" <(printf '%s\n' \
    '192.0.2.1/32' \
    '192.0.2.2/31' \
    '192.0.2.4/30' \
    '192.0.2.250/32' \
    '198.51.100.128/26' \
    '2001:db8::1/128' \
    '2001:db8::2/127' \
    '2001:db8::4/126' \
    '2001:db8:1::/126' \
    '2001:db8:abcd::42/128') || fail "unexpected allow CIDR bytes"
cmp "${deny_cidr}" <(printf '%s\n' \
    '192.0.2.3/32' \
    '192.0.2.4/31' \
    '192.0.2.6/32' \
    '203.0.113.64/30' \
    '203.0.113.250/32' \
    '2001:db8::3/128' \
    '2001:db8::4/127' \
    '2001:db8::6/128' \
    '2001:db8:eeee::42/128' \
    '2001:db8:ffff::/127') || fail "unexpected deny CIDR bytes"

for role in allow deny; do
    "${cidrmerge_binary}" --raw --representation ranges \
        "${temporary_directory}/cidr/${role}.cidr.txt" \
        >"${temporary_directory}/${role}.cidr-as-ranges.txt"
    cmp "${temporary_directory}/ranges/${role}.ranges.txt" \
        "${temporary_directory}/${role}.cidr-as-ranges.txt" ||
        fail "${role} CIDR and range artifacts disagree on exact coverage"

    "${cidrmerge_binary}" --raw --representation cidr \
        "${temporary_directory}/ranges/${role}.ranges.txt" \
        >"${temporary_directory}/${role}.ranges-as-cidr.txt"
    cmp "${temporary_directory}/cidr/${role}.cidr.txt" \
        "${temporary_directory}/${role}.ranges-as-cidr.txt" ||
        fail "${role} range and CIDR normalization is not idempotent"
done

empty_source="${temporary_directory}/empty-source.txt"
empty_output="${temporary_directory}/empty.txt"
: >"${empty_source}"
"${cidrmerge_binary}" --raw --representation ranges --checksum \
    --output "${empty_output}" "${empty_source}"
[[ ! -s "${empty_output}" ]] || fail "empty input did not produce zero bytes"

mixed_output="${temporary_directory}/mixed-role.txt"
printf '%s\n' \
    '192.0.2.250' \
    '198.51.100.0/31' \
    '2001:db8:2::1...2001:db8:2::3' \
    >"${mixed_output}"
printf '%s  %s\n' \
    'df9b6c6321d654fc2256b57107d1e8942e0fdd884a40e984cb2d45b669b26ebf' \
    'mixed-role.txt' \
    >"${mixed_output}.sha256"

"${acceptance_binary}" verify \
    "${allow_ranges}" "${deny_ranges}" "${allow_cidr}" "${deny_cidr}" \
    "${empty_output}" "${mixed_output}"

missing_directory="${temporary_directory}/failure-missing"
mkdir -p "${missing_directory}"
cp "${allow_ranges}" "${missing_directory}/allow.txt"
"${acceptance_binary}" expect-failure checksum-not-found allow \
    "${missing_directory}/allow.txt" -

missing_source="${temporary_directory}/missing-source.txt"
"${acceptance_binary}" expect-failure file-not-found allow \
    "${missing_source}" -

not_regular_source="${temporary_directory}/not-regular-source"
mkdir -p "${not_regular_source}"
"${acceptance_binary}" expect-failure not-regular allow \
    "${not_regular_source}" -

malformed_directory="${temporary_directory}/failure-malformed"
mkdir -p "${malformed_directory}"
cp "${allow_ranges}" "${malformed_directory}/allow.txt"
printf '%s  allow.txt\n' \
    '4D76E6DB1055BE34F628B491161DB2681F2F86F7A4EE1780E3415DA4F5AE63BC' \
    >"${malformed_directory}/allow.txt.sha256"
"${acceptance_binary}" expect-failure checksum-malformed allow \
    "${malformed_directory}/allow.txt" -

filename_directory="${temporary_directory}/failure-filename"
mkdir -p "${filename_directory}"
cp "${allow_ranges}" "${filename_directory}/allow.txt"
allow_range_digest="$(cut -c 1-64 <"${allow_ranges}.sha256")"
printf '%s  wrong.txt\n' \
    "${allow_range_digest}" \
    >"${filename_directory}/allow.txt.sha256"
"${acceptance_binary}" expect-failure checksum-filename-mismatch allow \
    "${filename_directory}/allow.txt" - wrong.txt

atomic_directory="${temporary_directory}/failure-atomic"
mkdir -p "${atomic_directory}"
"${cidrmerge_binary}" --raw --representation ranges --checksum \
    --output "${atomic_directory}/allow.txt" "${allow_source}"
"${cidrmerge_binary}" --raw --representation ranges --checksum \
    --output "${atomic_directory}/deny.txt" "${deny_source}"
expected_deny_digest="$(cut -c 1-64 <"${atomic_directory}/deny.txt.sha256")"
# CHANGE: The mutation is also invalid IP List Text, proving checksum verification wins before parsing.
printf 'not-an-ip-rule\n' >>"${atomic_directory}/deny.txt"
actual_deny_digest="$(sha256_file "${atomic_directory}/deny.txt")"
"${acceptance_binary}" expect-failure checksum-digest-mismatch deny \
    "${atomic_directory}/allow.txt" "${atomic_directory}/deny.txt" \
    "${expected_deny_digest}" "${actual_deny_digest}"

json_directory="${temporary_directory}/failure-json"
mkdir -p "${json_directory}"
"${cidrmerge_binary}" --json --representation ranges --checksum \
    --output "${json_directory}/allow.json" "${allow_source}"
"${acceptance_binary}" expect-failure invalid-rule allow \
    "${json_directory}/allow.json" -

cidrmerge_revision="$(repository_revision "${CIDRMERGE_PACKAGE}")" ||
    fail "unable to inspect cidrmerge Git revision"
admission_revision="$(repository_revision "${PACKAGE_ROOT}")" ||
    fail "unable to inspect swift-cidr-admission Git revision"
printf 'cidrmerge revision: %s\n' "${cidrmerge_revision}"
printf 'swift-cidr-admission revision: %s\n' "${admission_revision}"
printf 'artifact cardinality: ranges allow=%s deny=%s; cidr allow=%s deny=%s\n' \
    "$(wc -l <"${allow_ranges}" | tr -d '[:space:]')" \
    "$(wc -l <"${deny_ranges}" | tr -d '[:space:]')" \
    "$(wc -l <"${allow_cidr}" | tr -d '[:space:]')" \
    "$(wc -l <"${deny_cidr}" | tr -d '[:space:]')"
printf 'artifact SHA-256: ranges allow=%s deny=%s; cidr allow=%s deny=%s\n' \
    "$(cut -c 1-64 <"${allow_ranges}.sha256")" \
    "$(cut -c 1-64 <"${deny_ranges}.sha256")" \
    "$(cut -c 1-64 <"${allow_cidr}.sha256")" \
    "$(cut -c 1-64 <"${deny_cidr}.sha256")"
printf 'Gate 7 cidrmerge/admission pipeline acceptance passed.\n'
