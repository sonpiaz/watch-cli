#!/usr/bin/env bash
# Model SHA256 pin constants for watch-cli local transcribe path.
#
# Each pin matches the SHA256 of the binary blob hosted at the URL in
# the comment above it. install.sh --with-local downloads the file and
# verifies against the pin; mismatch aborts and does not write the
# partial file into ~/.watch-cli/models/.
#
# How the pin was produced:
#   curl -sSL <url> | shasum -a 256
#
# The HuggingFace CDN exposes a `x-linked-etag` header that is the
# SHA256 of LFS-stored binary content; the value below was verified
# against that header at implementation time (the `etag` returned by a
# HEAD request to the resolve URL). Upstream publishes a SHA1 on the
# whisper.cpp models page; watch-cli pins SHA256 to match the rest of
# the toolchain (`shasum -a 256` is the default on macOS).
#
# Idempotent: only load once per shell.
[[ -n "${WATCH_CLI_MODEL_CHECKSUMS_LOADED:-}" ]] && return 0
export WATCH_CLI_MODEL_CHECKSUMS_LOADED=1

# https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
# Size: 1624555275 bytes (≈ 1.62 GB)
# Source: x-linked-etag header on the resolve URL (HuggingFace LFS SHA256).
export WATCH_MODEL_SHA256_LARGE_V3_TURBO="1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"

# Download URL pinned alongside the hash so install.sh has one source of
# truth.
export WATCH_MODEL_URL_LARGE_V3_TURBO="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

# Filename on disk under $WATCH_MODELS_DIR.
export WATCH_MODEL_FILE_LARGE_V3_TURBO="ggml-large-v3-turbo.bin"
