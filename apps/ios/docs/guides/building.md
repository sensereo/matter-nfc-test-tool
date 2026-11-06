# Building the iOS app

Verified on 2026-11-06 against the build scripts. A completely fresh dependency
download and external-machine reproduction remain to be validated.

## Requirements

- A Mac with Xcode and command-line tools selected using `xcode-select`.
- Swift 6 for the core package; the app uses Swift 5 language mode.
- Ruby, Bundler, Git, Python 3, and network access for upstream build dependencies.
- A physical NFC-capable iPhone and an Apple signing team with NFC Tag Reading
  configured for your chosen Bundle ID. Simulator NFC testing is not supported.

The verified build environment uses Xcode 26.6 (17F113). The deployment target is iOS
17.0, which is a build setting, not a claim of tested iOS 17 compatibility.
The complete app/framework targets device arm64 only.

Run the following commands from `apps/ios/`:

```sh
bundle install
bash scripts/fetch-matter.sh
bash scripts/build-matter-framework.sh
bundle exec ruby scripts/generate-project.rb .scratch/dependencies/sdk-connectedhomeip Debug
open .scratch/AppProject/Debug/MatterNFCTestTool.xcodeproj
```

The SDK is fetched from `nrfconnect/sdk-connectedhomeip` and checked out at the
revision in `scripts/matter-revision.txt`. The build script fetches Darwin
submodules and bootstraps upstream tools when needed. It does not disable TLS
verification. Configure any required proxy or trusted CA externally.

An existing reviewed SDK checkout can be supplied as the first argument to both
build and generation scripts. Both must use the same checkout. The build checks
the revision and rejects tracked changes except upstream's generated Pigweed
environment file. Use a dedicated checkout; dependency preparation may update
submodules and generated tooling files there.

## Signing

Set your own values when generating a project, or configure signing in Xcode:

```sh
APP_BUNDLE_ID=com.example.matter-nfc-test-tool DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  bundle exec ruby scripts/generate-project.rb .scratch/dependencies/sdk-connectedhomeip Debug
```

The default ID is `org.sensereo.matter-nfc-test-tool`; no development team is
embedded in source. Generated project settings are local and ignored by Git.
Changing Bundle ID creates a separate app identity; do not assume access to a
different app's saved Fabric or device. Installing to a device is a separate action.

To check compilation without signing:

```sh
xcodebuild -project .scratch/AppProject/Debug/MatterNFCTestTool.xcodeproj \
  -scheme MatterNFCTestTool -configuration Debug -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath .scratch/AppBuild \
  CODE_SIGNING_ALLOWED=NO build
```

## Release configuration

Build and generate matching configurations; a Release app must not embed a
Debug framework:

```sh
bash scripts/build-matter-framework.sh .scratch/dependencies/sdk-connectedhomeip Release
bundle exec ruby scripts/generate-project.rb .scratch/dependencies/sdk-connectedhomeip Release
```

Open the project under `.scratch/AppProject/Release/`. Each generated project
contains only its selected configuration. Release generation does not constitute
TestFlight or public-binary readiness. Dependency notices must be collected for
binary redistribution; see the repository-root third-party notices.

No generator reads personal setup payloads, network datasets, or private keys.
The only bundled test credential is the public FFF1 PAA certificate from the
pinned SDK. Its private key is not copied.
