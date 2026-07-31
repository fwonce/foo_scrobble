#!/bin/bash
# Download foobar2000 SDK for building foo_scrobble
# Usage: ./setup.sh [proxy_url]
#
# If you need a proxy to download, pass it as argument:
#   ./setup.sh http://127.0.0.1:7890

set -e

SDK_VERSION="2025-03-07"
SDK_URL="https://www.foobar2000.org/downloads/SDK-${SDK_VERSION}.7z"
SDK_DIR="sdk"

if [ -d "$SDK_DIR/foobar2000" ]; then
    echo "SDK already exists at $SDK_DIR/. Skipping download."
    echo "To re-download, run: rm -rf $SDK_DIR && $0"
    exit 0
fi

echo "Downloading foobar2000 SDK $SDK_VERSION..."

CURL_ARGS=(-L -o /tmp/foobar2000_sdk.7z)
if [ -n "$1" ]; then
    echo "Using proxy: $1"
    CURL_ARGS+=(-x "$1")
fi

curl "${CURL_ARGS[@]}" "$SDK_URL"

echo "Extracting..."

# Try 7z first, fall back to python
if command -v 7z &>/dev/null; then
    7z x /tmp/foobar2000_sdk.7z -o"$SDK_DIR" -y >/dev/null
elif command -v 7za &>/dev/null; then
    7za x /tmp/foobar2000_sdk.7z -o"$SDK_DIR" -y >/dev/null
elif python3 -c "import py7zr" 2>/dev/null; then
    python3 -c "
import py7zr
with py7zr.SevenZipFile('/tmp/foobar2000_sdk.7z', mode='r') as z:
    z.extractall(path='$SDK_DIR')
"
else
    echo "ERROR: Need 7z or py7zr to extract .7z files."
    echo "Install via: brew install p7zip"
    rm -f /tmp/foobar2000_sdk.7z
    exit 1
fi

rm -f /tmp/foobar2000_sdk.7z
echo "✓ SDK $SDK_VERSION ready at $SDK_DIR/"
echo ""
echo "Next: create src/foo_scrobble/Keys.local.h with your Last.fm API key."
echo "See Keys.local.h.template for the format."
