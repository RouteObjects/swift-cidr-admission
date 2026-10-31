# Releasing swift-cidr-admission

This maintainer guide prepares a signed `MAJOR.MINOR.PATCH` release of the
`CIDRAdmission` Swift library. The package has no executable or binary release
assets. The Release workflow always stops at a draft; a maintainer publishes
that draft only after Craig's explicit approval.

## Prepare and validate a candidate

Start from a clean `main` that matches its remote. Versions do not use a leading
`v`, and every version has a reviewed release-notes file. Use a normal release
branch, not a worktree:

```sh
version=0.3.1
candidate_ref="release/${version}"
git switch main
git pull --ff-only origin main
git switch -c "${candidate_ref}"
```

Use Swift 6.3 or later for the complete release gate, including benchmarks.
The library's Swift 6.2 minimum is validated separately by Linux CI in both
debug and release configurations. Update the README, release notes, this guide,
and the Release workflow's default version. Preserve historical notes and
measurements, and do not refresh unrelated dependencies.

Review and signed-commit the candidate changes before running the gate: it
requires a clean checkout and builds the benchmark package from committed
`HEAD`. Save validation logs outside the repository and record the candidate
SHA and results in the PR rather than changing tracked files during validation.

Use an isolated `cidrmerge` 0.2.0 checkout for local acceptance, leaving any
in-progress sibling checkout untouched. Verify the producer's immutable
release commit before building it:

```sh
cidrmerge_checkout="$(mktemp -d)"
git clone --branch 0.2.0 --depth 1 \
  https://github.com/RouteObjects/cidrmerge.git "${cidrmerge_checkout}"
test "$(git -C "${cidrmerge_checkout}" rev-parse HEAD)" = \
  "117b87b25ded47d5cc74e10e165c1bba8a94458f"
git status --short --branch
CIDRMERGE_PACKAGE="${cidrmerge_checkout}" ./scripts/check-release.sh "${version}"
```

The release gate checks the root and cidrmerge-pipeline locks, debug and release
builds and tests, the pinned offline cidrmerge pipeline, the SwiftNIO example,
the benchmark target, the public symbol graph, and a temporary external
consumer. The consumer preserves representative legacy initializer and JSON
behavior while exercising both checksum policies; it is intentionally not a
claim that every 0.1 source expression remains compatible.

Review every file and reachable commit included by the tag. Do not continue if
the tree or history contains credentials, private paths, local dependency
overrides, or internal-only material.

## Run the no-tag dry run

Push the candidate branch and open a PR targeting `main`. Require automatic
Linux and benchmark CI to pass, then manually dispatch CI so the macOS and iOS
checks run. Explicitly select the candidate branch for both CI and the Release
dry run; otherwise GitHub can validate the default branch instead of the
release candidate. A manual Release workflow runs the complete gate but cannot
create a tag or a GitHub Release.

```sh
git push --set-upstream origin "${candidate_ref}"
gh workflow run ci.yml --repo RouteObjects/swift-cidr-admission \
  --ref "${candidate_ref}"
gh workflow run release.yml \
  --repo RouteObjects/swift-cidr-admission \
  --ref "${candidate_ref}" \
  -f version="${version}"
gh run list --repo RouteObjects/swift-cidr-admission --limit 10
```

Review the hosted logs and confirm the source checkout, cidrmerge `0.2.0`
pipeline, dependency locks, consumer check, example, benchmark compile, public
symbols, macOS build, iOS build, and Linux tests all passed. Check each run's
head SHA against the candidate commit. The manually dispatched macOS/iOS job
must succeed, not be skipped; the Release workflow's draft-publication job
must remain skipped. Any corrective commit requires renewed validation of the
latest candidate.

Stop after reporting the PR and validation results unless separately approved
to merge, tag, or publish. Retain the temporary producer checkout until its
validation logs have been reviewed, then remove only that temporary directory.

## Sign the tag and review the draft

After separate approval, merge the candidate PR and fast-forward local `main`.
Verify that it includes the reviewed candidate, and rerun validation if the
merged source differs from what was tested. Obtain explicit approval before
creating the release tag. Confirm local and remote `main` identify the same
reviewed commit, then create the
annotated SSH-signed tag:

```sh
git switch main
git pull --ff-only origin main
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git tag -s "${version}" -m "swift-cidr-admission ${version}"
git tag -v "${version}"
git push origin "${version}"
```

The tag-triggered workflow verifies that GitHub accepts the tag signature and
that the tagged commit is reachable from `origin/main`. It reruns the release
gate and creates a latest-eligible, non-prerelease **draft** named
`swift-cidr-admission <version>` using only
`Documentation/ReleaseNotes/<version>.md`. It uploads no assets and never
publishes automatically.

Review the draft body, package source at the tag, CI results, and a clean
external SwiftPM resolution. Obtain explicit final approval before publishing
the draft as the latest, non-prerelease Release.

Swift Package Index is a useful public documentation and compatibility leaf,
but indexing backlog never blocks publication or downstream development.

## Failure and rollback policy

- Before pushing the tag, fix the candidate and rerun the complete dry run.
- After pushing the tag, never delete, move, or overwrite it. The semantic tag
  is already available to SwiftPM consumers even while the Release is a draft.
- Rerun transient workflow failures against the same tag. Correct source or
  release-note defects in the next patch version.
- After publication, never rewrite the tag or Release. Publish a new patch
  version and use the repository's security process when impact warrants it.
