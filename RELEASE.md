# Releasing PipFlow

## Build and package locally

On macOS 13.4 or later, install Xcode Command Line Tools and CMake. Then run these commands from this folder.

```sh
./build.sh
./scripts/package-release.sh
```

The first build downloads and verifies the pinned decoder source and Granite Speech model. The build produces `PipFlow.app`. The packaging script verifies the bundled model and code signature, then writes the app ZIP and its SHA-256 checksum to `release-assets/`. The model and decoder ship inside the app, so dictation can run offline after extraction. Build on Apple Silicon for an `arm64` download and on Intel for an `x86_64` download.

## GitHub Releases

Commit the source and workflow from this folder to the intended GitHub repository. The ignore file keeps `vendor/`, `PipFlow.app`, and `release-assets/` out of Git. Confirm your source licensing choice before making the repository public. The app bundle includes the third-party license files.

Run **Build macOS release** from the Actions tab for a test build. The workflow produces separate Apple Silicon and Intel downloads. To create a draft under **Releases**, push a version tag that matches `CFBundleShortVersionString` in `Info.plist`. For this version, use `v1.2.0`.

```sh
git tag v1.2.0
git push origin v1.2.0
```

Review the draft and exercise both builds before publishing. GitHub also attaches separate source archives automatically.

## Developer ID signing and notarization

The default workflow produces ad-hoc signed preview builds. macOS Gatekeeper may block a downloaded preview. For public distribution, sign and notarize on a Mac with a **Developer ID Application** certificate and an existing `notarytool` keychain profile.

```sh
PIP_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
PIP_NOTARY_PROFILE='pipflow-notary' \
./scripts/package-release.sh
```

Run this on each build architecture, then replace the corresponding preview ZIP and checksum in the draft and update its release notes. The script signs a temporary copy with the hardened runtime, notarizes and staples it, then creates the final ZIP.

[GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) · [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
