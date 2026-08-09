# Releasing swift-cidr-admission

This maintainer guide prepares a signed `MAJOR.MINOR.PATCH` release of the
`CIDRAdmission` Swift library. The package has no executable or binary release
assets. The Release workflow always stops at a draft; a maintainer publishes
that draft only after Craig's explicit approval.

## Prepare and validate main

Start from a clean `main` that matches its remote. Versions do not use a leading
`v`, and every version has a reviewed release-notes file:

```sh
version=0.2.0
git switch main
git pull --ff-only origin main
git status --short --branch
CIDRMERGE_PACKAGE=../cidrmerge ./scripts/check-release.sh "${version}"
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

Require automatic Linux CI to pass, then manually dispatch CI so the macOS and
iOS checks run. Dispatch the Release workflow with the intended version. A
manual Release workflow runs the complete gate but cannot create a tag or a
GitHub Release.

```sh
gh workflow run ci.yml --repo RouteObjects/swift-cidr-admission
gh workflow run release.yml \
  --repo RouteObjects/swift-cidr-admission \
  -f version="${version}"
gh run list --repo RouteObjects/swift-cidr-admission --limit 10
```

Review the hosted logs and confirm the source checkout, cidrmerge `0.2.0`
pipeline, dependency locks, consumer check, example, benchmark compile, public
symbols, macOS build, iOS build, and Linux tests all passed.

## Sign the tag and review the draft

Obtain explicit approval before creating the release tag. Confirm local and
remote `main` still identify the same reviewed commit, then create the
annotated SSH-signed tag:

```sh
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
