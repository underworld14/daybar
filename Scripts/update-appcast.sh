#!/usr/bin/env bash
# Regenerate site/appcast.xml from a release ZIP (maintainer helper).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-/tmp/bin}"
ZIP_PATH="${1:-}"
VERSION="${2:-}"
TAG="${3:-}"

if [ -z "$ZIP_PATH" ] || [ -z "$VERSION" ] || [ -z "$TAG" ]; then
  echo "Usage: $0 <path-to-zip> <version> <git-tag>" >&2
  echo "Example: $0 DayBar-v0.3.0-macOS.zip 0.3.0 v0.3.0" >&2
  exit 1
fi

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  curl -fsSL -o /tmp/Sparkle.tar.xz \
    "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"
  tar -xf /tmp/Sparkle.tar.xz -C /tmp
fi

mkdir -p "$ROOT/releases"
if [ -f "$ROOT/site/appcast.xml" ]; then
  cp "$ROOT/site/appcast.xml" "$ROOT/releases/appcast.xml"
fi
cp "$ZIP_PATH" "$ROOT/releases/"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/underworld14/daybar/releases/download/${TAG}/" \
  --link "https://underworld14.github.io/daybar/" \
  "$ROOT/releases/"

cp "$ROOT/releases/appcast.xml" "$ROOT/site/appcast.xml"
echo "Updated $ROOT/site/appcast.xml"
