#!/usr/bin/env bash
set -euo pipefail
TOFU_VERSION="1.12.6"
ARCHIVE="tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
SUMS_FILE="tofu_$TOFU_VERSION""_SHA256SUMS"
BASE_URL="https://get.opentofu.org/tofu/$TOFU_VERSION"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$RUNNER_TEMP/bin"
mkdir -p "$BIN_DIR"
curl --fail --silent --show-error --location "$BASE_URL/$ARCHIVE" --output "$TMP_DIR/$ARCHIVE"
curl --fail --silent --show-error --location "$BASE_URL/$SUMS_FILE" --output "$TMP_DIR/SHA256SUMS"
(
  cd "$TMP_DIR"
  grep -F "$ARCHIVE" SHA256SUMS | sha256sum --check -
)
tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR" tofu
install -m 0755 "$TMP_DIR/tofu" "$BIN_DIR/tofu"
"$BIN_DIR/tofu" version
rm -rf "$TMP_DIR"
