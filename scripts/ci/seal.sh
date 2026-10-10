#!/usr/bin/env bash
set -euo pipefail
MODE="$1"
if [[ "$MODE" == "seal" ]]; then
  [[ "$#" -eq 4 ]] || { echo "Usage: seal.sh seal input sealed-file hmac-file | seal.sh open sealed-file hmac-file output" >&2; exit 2; }
  INPUT="$2"
  SEALED="$3"
  HMAC_FILE="$4"
else
  [[ "$MODE" == "open" && "$#" -eq 4 ]] || { echo "Usage: seal.sh seal input sealed-file hmac-file | seal.sh open sealed-file hmac-file output" >&2; exit 2; }
  SEALED="$2"
  HMAC_FILE="$3"
  OUTPUT="$4"
fi
: "${TOFU_ARTIFACT_ENCRYPTION_KEY:?missing encryption key}"
: "${TOFU_ARTIFACT_HMAC_KEY:?missing HMAC key}"
[[ "$TOFU_ARTIFACT_ENCRYPTION_KEY" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Encryption key must be 64 hex characters." >&2; exit 2; }
[[ "$TOFU_ARTIFACT_HMAC_KEY" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "HMAC key must be 64 hex characters." >&2; exit 2; }
hmac_file() {
  openssl dgst -sha256 -mac HMAC -macopt "hexkey:$TOFU_ARTIFACT_HMAC_KEY" "$1" | awk '{print $NF}'
}
case "$MODE" in
  seal)
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$INPUT" -out "$SEALED" -pass env:TOFU_ARTIFACT_ENCRYPTION_KEY
    hmac_file "$SEALED" > "$HMAC_FILE"
    ;;
  open)
    EXPECTED="$(cat "$HMAC_FILE")"
    [[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid artifact authentication tag." >&2; exit 1; }
    ACTUAL="$(hmac_file "$SEALED")"
    [[ "$ACTUAL" == "$EXPECTED" ]] || { echo "Artifact authentication failed." >&2; exit 1; }
    openssl enc -d -aes-256-cbc -pbkdf2 -in "$SEALED" -out "$OUTPUT" -pass env:TOFU_ARTIFACT_ENCRYPTION_KEY
    ;;
  *)
    echo "Usage: seal.sh seal input sealed-file hmac-file output | seal.sh open sealed-file hmac-file output" >&2
    exit 2
    ;;
esac
