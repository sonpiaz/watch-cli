#!/usr/bin/env bash
# Single source of truth for the watch-cli version. Sourced by every
# bin/* script (for --version) and by lib/env.sh (for the User-Agent
# header sent on Kyma calls).
#
# Release workflow (.github/workflows/release.yml) checks
# WATCH_CLI_VERSION here against the pushed git tag and refuses to
# publish on mismatch. CI on main runs the same check against the
# latest v* tag. See docs/releases.md for the full release contract.
#
# To cut a release: bump WATCH_CLI_VERSION below, open a release PR
# titled `release: vX.Y.Z`, merge, then tag the merge commit `vX.Y.Z`
# and push. The tag fires the release workflow.

export WATCH_CLI_VERSION="0.3.0"
export WATCH_CLI_VERSION_STRING="watch-cli v${WATCH_CLI_VERSION}"
