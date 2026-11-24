#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p vendor
download() {
  [[ -f "$2" ]] && return
  curl -fL --proto '=https' --proto-redir '=https' --retry 2 "$1" -o "$2.part"
  mv "$2.part" "$2"
}
sdk="$(xcrun --show-sdk-path)"
download https://codeload.github.com/handy-computer/transcribe.cpp/tar.gz/refs/tags/v0.4.1 vendor/transcribe.tar.gz
download https://huggingface.co/vladers/granite-speech-5.0-470m-turboctc-GGUF/resolve/88845afaa7beadca4b9ec545df0dd7332349ab88/granite-speech-5.0-470m-turboctc-Q8_0.gguf vendor/granite-q8.gguf
shasum -a 256 -c SHA256SUMS
stage=$(mktemp -d "$PWD/vendor/package.XXXXXXXX")
cleanup() {
  if [[ -d "$stage/previous.app" && ! -d PipFlow.app ]]; then
    printf 'Previous app preserved at %s/previous.app\n' "$stage" >&2
    return
  fi
  rm -rf "$stage"
}
trap cleanup EXIT
# Compile the verified archive rather than reusing an editable extracted tree.
tar -xzf vendor/transcribe.tar.gz -C "$stage"
granite_src="$stage/transcribe.cpp-0.4.1"
cmake -S "$granite_src" -B "$stage/engine" -DCMAKE_BUILD_TYPE=Release -DTRANSCRIBE_BUILD_TESTS=OFF -DTRANSCRIBE_METAL=OFF -DGGML_NATIVE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=13.4 "-DCMAKE_OSX_SYSROOT=$sdk" "-DCMAKE_CXX_FLAGS=-isystem $sdk/usr/include/c++/v1"
cmake --build "$stage/engine" --target transcribe-cli -j 4
bundle="$stage/PipFlow.app"
contents="$bundle/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.4" -module-cache-path "${TMPDIR:-/tmp}/murmur-swiftcache" \
  Sources/*.swift -framework Accelerate -o "$contents/MacOS/PipFlow"
mkdir -p "$contents/Helpers"
cp "$stage/engine/bin/transcribe-cli" "$contents/Helpers/"
codesign --force --sign "${PIP_SIGNING_IDENTITY:--}" "$contents/Helpers/transcribe-cli"
cp vendor/granite-q8.gguf Assets/LICENSE-Granite.txt "$contents/Resources/"
cp "$granite_src/LICENSE" "$contents/Resources/LICENSE-transcribe.cpp.txt"
cp "$granite_src/THIRD-PARTY-LICENSES.md" "$contents/Resources/transcribe-third-party.md"
cp Info.plist "$contents"
cp Assets/Pip.icns Assets/PipMenu.svg "$contents/Resources"
codesign --force --sign "${PIP_SIGNING_IDENTITY:--}" "$bundle"
codesign --verify --deep --strict "$bundle"
if [[ -d PipFlow.app ]]; then mv PipFlow.app "$stage/previous.app"; fi
if ! mv "$bundle" PipFlow.app; then
  if [[ -d "$stage/previous.app" ]]; then mv "$stage/previous.app" PipFlow.app; fi
  exit 1
fi
