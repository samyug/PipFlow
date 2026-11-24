#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app=PipFlow.app
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
arch=$(lipo -archs "$app/Contents/MacOS/PipFlow")
helper="$app/Contents/Helpers/transcribe-cli"
if [[ "$arch" != arm64 && "$arch" != x86_64 ]] || [[ "$(lipo -archs "$helper")" != "$arch" ]]; then
  echo 'Expected matching Apple Silicon or Intel app and decoder binaries.' >&2
  exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Expected a three-part app version.' >&2
  exit 1
fi
if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_TYPE:-}" == tag && "v$version" != "$GITHUB_REF_NAME" ]]; then
  echo 'The Git tag must match CFBundleShortVersionString.' >&2
  exit 1
fi

codesign --verify --deep --strict "$app"
model="$app/Contents/Resources/granite-q8.gguf"
for notice in LICENSE-Granite.txt LICENSE-transcribe.cpp.txt transcribe-third-party.md; do
  test -s "$app/Contents/Resources/$notice"
done
# Read the same expected model hash used by the source build.
model_hash=$(awk '$2 == "vendor/granite-q8.gguf" {print $1}' SHA256SUMS)
printf '%s  %s\n' "$model_hash" "$model" | shasum -a 256 -c

mkdir -p release-assets
stage=$(mktemp -d "$PWD/release-assets/.package.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
archive="PipFlow-$version-macOS-$arch.zip"
package_app="$app"
if [[ -n "${PIP_NOTARY_PROFILE:-}" ]]; then
  : "${PIP_SIGNING_IDENTITY:?Set PIP_SIGNING_IDENTITY to your Developer ID Application identity}"
  package_app="$stage/PipFlow.app"
  ditto "$app" "$package_app"
  codesign --force --options runtime --timestamp --sign "$PIP_SIGNING_IDENTITY" "$package_app/Contents/Helpers/transcribe-cli"
  codesign --force --options runtime --timestamp --entitlements scripts/release.entitlements --sign "$PIP_SIGNING_IDENTITY" "$package_app"
  codesign --verify --deep --strict "$package_app"
  ditto -c -k --keepParent "$package_app" "$stage/notary.zip"
  xcrun notarytool submit "$stage/notary.zip" --keychain-profile "$PIP_NOTARY_PROFILE" --wait
  xcrun stapler staple "$package_app"
  xcrun stapler validate "$package_app"
fi

ditto -c -k --keepParent "$package_app" "$stage/$archive"
(cd "$stage" && shasum -a 256 "$archive" > "$archive.sha256")
mv "$stage/$archive" "$stage/$archive.sha256" release-assets/
printf '%s\n' "release-assets/$archive"
