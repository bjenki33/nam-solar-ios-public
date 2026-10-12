# Nam Solar for iPhone

Version 1.4.9 / build 20 sets the two upper overview bands to 20pt, with the
clock/date/grid-status centered inside the first band. The bottom margin stays
at 16pt. Unusually tall status content can expand both upper bands equally to
avoid overlap. Header, fonts, data, artwork and minimum diagram size are unchanged.
Small viewports scroll rather than clip devices. Android is unchanged.

Version 1.4.8 / build 19 reduces the two upper overview gaps: toolbar-to-cards
(including clock/date/grid status) and cards-to-diagram. Both follow the measured
status height, normally about 28pt instead of 36pt. The diagram-to-bottom margin
stays at its original 16pt. Toolbar, logo, card type/data and minimum diagram size
are unchanged; small viewports scroll to keep devices readable. Android is unchanged.

Version 1.4.7 / build 18 moves the overview clock/date/grid-status below the
toolbar and above the daily cards. The complete toolbar-to-card band (including
the status row) matches the card-to-diagram gap, using the measured status height.
Toolbar, logo, card typography, bottom margin and minimum diagram size remain
unchanged; small viewports scroll rather than shrink or clip. Android is unchanged.

Version 1.4.6 / build 17 uses the approved NAM SOLAR logo as the home-screen
icon. The overview clock/date/grid-status returns between the daily summary
and energy-flow diagram. Toolbar, type, margins, diagram size, charts and
authentication are unchanged. Android intentionally keeps its status at the top.

Version 1.4.5 moves the overview clock/date/grid-status row directly below the
toolbar and above the daily metric cards. Fonts, outer margins, diagram size,
header logo, authentication and chart/data behavior remain unchanged.

Version 1.4.4 uses the owner's approved NAM SOLAR header logo, enlarged on the
left with smaller 11pt tab labels. The toolbar remains 58pt tall. The home-screen
icon, dashboard layout, authentication and all data/chart behavior are unchanged.

Version 1.4.3 also isolates the history calendar's draft/month from live updates.
Date selection is confirmed explicitly before applying a history request. Pull-to-refresh
has been removed; live WebSocket updates, automatic reconnection and explicit recovery/history buttons remain.

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

## Version 1.4.3 (14)

- SOC history reads Recorder five-minute means, matching the web's data source.
  Missing/null statistic buckets stay missing; aggregate values are labelled.
  Inspecting SOC selects a recorded bucket-end timestamp, not an interpolated
  percentage or the next bucket's mean at the previous endpoint.
- Raw history retains the last available state up to the actual unavailable
  boundary and the fixed request end, without inventing readings during outages.
- A fast horizontal one-finger swipe pans a zoomed chart without changing zoom.
  Hold-and-drag still scrubs; vertical scrolling, pinch and double tap remain.
- Time/value inspectors sit above the plots and reserve their space before
  selection, so inspecting a value does not move the plot under the finger.
- Synthetic regression tests cover long flat SOC sections, actual gaps,
  statistics provenance and panning/inspection gesture separation.

## Preserved Features

- Web-matching MDI navigation icons: solar-power, battery-heart-variant,
  chart-line and lan-check. Tab labels are 11pt; the approved 54pt header logo
  has a 60pt left slot within the unchanged 58pt toolbar. Each entire tab column
  remains tappable, including the space around its icon and label.
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

`nam-solar-app-icon.png` is the approved NAM SOLAR header logo centered at
84 percent on an opaque 1024px blue gradient square (#65D7FC to #0252E2),
sampled from the old icon's light top and dark bottom. The artwork is not
redrawn or clipped; system corner masks remain separate. Do not replace
it when editing other UI.

`nam-solar-header-logo.png` is the separately approved transparent header logo,
identical to the Android 1.0.4 artwork. SHA256:
`a40b12c09e6b0e32044446446781e6166c8f224b60381ed92f5ee3f0847dc1ee`.

MDI vectors retain their attribution and Apache 2.0 notices in
`SolarMetricIcon-NOTICE.txt`, `MDI-LICENSE.txt` and `Apache-2.0.txt`.
Those licenses cover the third-party vectors, not the entire application or
the owner's artwork. No additional reuse license is granted for the app/artwork.

No Home Assistant, website, router or inverter configuration is changed by
the public build. The app remains separate from the owner's server projects.
