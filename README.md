# Nam Solar for iPhone

Native, read-only SwiftUI solar monitoring app. Requires iOS 26.0 or later.
This is a clean public build repository authorized by the owner. The original
private repository, its history and personal work journal remain private.

## Authentication and Data

- The production app requires an authorized Home Assistant login at
  https://solar.bocphot.me. Publishing the app does not grant access to its data.
- No password, access token, refresh token, signing key or real telemetry export
  is included. Tokens obtained at runtime are stored in the iPhone Keychain.
- TLS validation and same-origin redirect checks remain enabled.
- The app only reads states, history and recorder statistics. It does not send
  Home Assistant service calls or commands to the inverter.
- Test data is synthetic and gated behind Debug builds, not shipped in Release.
- Public source reveals the server hostname and sensor identifiers. It is not
  a substitute for server-side authentication and authorization.

## Version 1.4.2 (13)

- Web-matching MDI navigation icons: solar-power, battery-heart-variant,
  chart-line and lan-check. Tab labels are 12pt; NAM is centered over SOLAR.
- The system footer reads the version and build from the app bundle.
- The home-screen icon is the owner's supplied design with its outer frame
  removed. Its blue background reaches all four square edges; iOS masks corners.
- Existing balanced layout, readable consumption columns, device power/history,
  day/range energy history and chart tap/hold/drag/zoom are retained.
- Battery display remains positive while charging and negative while discharging.
  Live detail readings do not wait for history requests to finish.

## Build and Test

Use a Mac with Xcode and the iOS 26 SDK:

```sh
bash build-ios.sh
```

The script generates opaque app artwork and the Xcode project, runs Swift
package tests plus native/unit/UI tests on large and compact iPhone simulators,
then archives the real ARM64 Release app. The workflow uses a standard
GitHub-hosted macOS runner. No credentials or signing secrets are needed in CI.

Outputs: `build/NamSolar-<bundle-version>-iOS26-unsigned.ipa` and `build/SHA256.txt`.
An unsigned IPA must be signed before installation, for example with Sideloadly.
Simulator tests do not replace real-iPhone login/live/background/network testing.

For every release, update `project.yml` version/build and verify the archived
Info.plist, visible system footer and IPA filename agree before delivery.
Run `python3 verify-ipa.py <ipa-path>` to inspect the Release package.

## Artwork and Licensing

`nam-solar-app-icon.png` is the owner's chosen borderless icon. Do not replace
it when editing other UI. SHA256:
`1b2b33d8ac64f6016efeae784324a8c9f58fc28430e60a02ad3437628cec5167`.

MDI vectors retain their attribution and Apache 2.0 notices in
`SolarMetricIcon-NOTICE.txt`, `MDI-LICENSE.txt` and `Apache-2.0.txt`.
Those licenses cover the third-party vectors, not the entire application or
the owner's artwork. No additional reuse license is granted for the app/artwork.

No Home Assistant, website, router or inverter configuration is changed by
the public build. The app remains separate from the owner's server projects.
