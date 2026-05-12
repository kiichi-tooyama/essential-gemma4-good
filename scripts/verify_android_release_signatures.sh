#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <essential-apk> <pixel-chat-apk>" >&2
  exit 2
fi

essential_apk="$1"
pixel_chat_apk="$2"

if [[ ! -f "$essential_apk" ]]; then
  echo "Essential APK not found: $essential_apk" >&2
  exit 2
fi

if [[ ! -f "$pixel_chat_apk" ]]; then
  echo "Pixel Chat APK not found: $pixel_chat_apk" >&2
  exit 2
fi

apksigner_bin="${APKSIGNER:-}"
if [[ -z "$apksigner_bin" ]]; then
  if command -v apksigner >/dev/null 2>&1; then
    apksigner_bin="$(command -v apksigner)"
  else
    apksigner_bin="$(find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/build-tools" -name apksigner -type f | sort -V | tail -1)"
  fi
fi

if [[ -z "$apksigner_bin" || ! -x "$apksigner_bin" ]]; then
  echo "apksigner was not found. Set ANDROID_HOME or APKSIGNER." >&2
  exit 2
fi

fingerprint() {
  "$apksigner_bin" verify --print-certs "$1" \
    | awk -F': ' '/Signer #1 certificate SHA-256 digest/ { print $2; exit }'
}

essential_fp="$(fingerprint "$essential_apk")"
pixel_fp="$(fingerprint "$pixel_chat_apk")"

if [[ -z "$essential_fp" || -z "$pixel_fp" ]]; then
  echo "Could not read APK signing certificate fingerprints." >&2
  exit 1
fi

echo "Essential SHA-256:  $essential_fp"
echo "Pixel Chat SHA-256: $pixel_fp"

if [[ "$essential_fp" != "$pixel_fp" ]]; then
  echo "Signature mismatch. Pixel Feature Chat cannot bind to Essential's signature-protected service." >&2
  exit 1
fi

echo "OK: Essential and Pixel Chat are signed with the same certificate."
