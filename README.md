# Wishare

LAN-only peer-to-peer file and folder sharing for **Linux, Android and Windows**,
built with Flutter and designed with Material 3 Expressive tokens.

No account, no cloud, no relay: devices on the same network discover each other,
pair once with a QR code (certificate fingerprint + PIN), then exchange files
directly over HTTPS with resumable chunks and SHA-256 verification.

## Current status (v0.4.1)

Implemented:

- Update manager: checks the latest stable GitHub release once on startup
  (cached for 15 minutes, opt-out via Settings) and on demand. A small badge
  on the Settings icon marks an available update; the Updates card in Settings
  shows version, release notes and a Download button for the current platform.
  On Android the APK is enqueued in the system DownloadManager (background
  download, completion notification, visible in the Downloads app); desktop
  opens the asset in the browser. A release-page fallback is used when no
  matching asset exists.
- M3 Expressive theme layer: exact radius scale, emphasized type built from
  published tokens, colour-role mapping, dynamic colour with static baseline
  fallback, contrast levels, and spring values mapped to Flutter's
  `SpringSimulation`.
- Shell: Send and Receive in a bottom navigation bar, with History and Settings
  in the app bar's trailing edge and pairing in an extended FAB above the bar.
  History, Settings, Pair and Scan are pushed pages, so back returns to the
  previous tab; tab scroll positions are preserved. Send to lists every known
  device with paired ones on top: pick files or a folder and tap a paired
  device to send, or use the inline Pair button for nearby devices. Bottom
  sheets on phones, dialogs on desktop.
- Device discovery via a DNS-SD mDNS querier and responder
  (`_wishare._tcp.local`) plus a UDP broadcast heartbeat, with manual IP/QR
  fallback. Both paths are bound to the same LAN interface as the QR address,
  and the Send tab has a **Scan again** action when nothing shows up. On
  desktop the Pair button opens manual entry directly, since the camera scanner
  plugin has no Linux/Windows implementation.
- Self-signed P-256 certificate generation and TOFU fingerprint pinning.
- Three pairing paths: QR scan, request/approve with a nearby device (no code
  at all), and manual IP/PIN/fingerprint entry. All show the certificate
  fingerprint for confirmation.
- HTTPS receiver and sender: pairing token, transfer offers, chunk streaming
  with resume, checksum verification, safe folder extraction, transfer history.
- Android foreground service declaration, Wi-Fi lock, Wi-Fi multicast lock for
  mDNS and "Share to Wishare" intent intake; desktop window setup with a tray
  icon and menu.
- Persistent peers, transfers and settings via `shared_preferences` + JSON.

Still out of scope:

- Packaged installers/signing (release CI attaches zips and APKs; MSIX and deb
  packaging templates live in `packaging/`).
- A full manual accessibility audit (semantics are in place, but not audited
  on screen readers).

## Run

```bash
flutter pub get
flutter run -d linux        # or -d android / -d windows (Windows host required)
```

## Pairing (two devices on the same network)

1. On the device that will **receive** files, tap the **Pair** FAB, then
   **Show my code** in the top bar, then **Generate pairing code**. It shows a
   QR code, a single-use 6-digit PIN and the certificate fingerprint.
2. On the device that will **send** files, tap the **Pair** FAB and point the
   camera at the QR code shown on the receiver.
3. Check the name, address and shortened fingerprint in the confirmation
   dialog, then tap **Connect**. The fingerprint is pinned for later transfers.

No camera? Tap the keyboard button in the scanner and enter the receiver's IP
address, port (45821), PIN and full fingerprint by hand. **Fetch fingerprint
from device** fills the fingerprint over HTTPS, but still compare it with the
one shown on the receiver before connecting.

### Pairing without a QR code

Nearby devices found by mDNS/UDP appear in the **Send** tab automatically. Tap
**Pair** on one of them: the receiving device gets a **Pairing request** dialog
showing the sender's name and certificate fingerprint, with **Approve** and
**Decline** actions. The sender waits for the answer; a session token is issued
only after the receiver approves. No QR code and no PIN are involved. Requests
expire after two minutes, and at most eight can be pending. The sender can tap
**Cancel** while waiting, and brief network interruptions no longer abort the
wait. This is the recommended path when both devices are on the same network.
A nearby device without a verifiable fingerprint cannot use this path; use the
QR code or manual entry instead.

Release builds:

```bash
flutter build apk --release     # uses debug key unless WISHARE_KEYSTORE_PATH,
                                # WISHARE_STORE_PASSWORD, WISHARE_KEY_ALIAS and
                                # WISHARE_KEY_PASSWORD are set
flutter build linux --release
# flutter build windows --release  (Windows host required)
```

Publishing a GitHub release (v0.4.0):

```bash
git tag v0.4.0 && git push origin v0.4.0
```

`.github/workflows/release.yml` builds Windows, Linux and Android in parallel,
then attaches `wishare-0.4.0-windows-x64.zip`, `wishare-0.4.0-linux-x64.zip`,
`wishare-0.4.0-android.apk`, the three per-ABI APKs and `SHA256SUMS.txt` to the
release. The workflow can also be started manually with `workflow_dispatch` and
a tag name. `dist/` holds the older local assets; v0.4.0 assets are produced by
CI when the tag is pushed. The update manager reads these releases through
`https://api.github.com/repos/ibro-3/wishare/releases/latest`; keep asset names
in the `wishare-<version>-<platform>.<ext>` form so the platform picker works.

Tests and CI:

```bash
flutter analyze
flutter test
```

`.github/workflows/ci.yml` runs formatting, analysis, tests and debug builds
for Android, Linux and Windows (the Windows job runs on a Windows runner).

The end-to-end test starts a real HTTPS server and client on localhost, pairs
them, and transfers a nested folder with checksum verification.

## Architecture

```
lib/core/theme      design tokens (colour, type, shape, motion)
lib/core/crypto     certificate generation, fingerprints, IDs
lib/core/network    discovery, pairing payload, server, client, transfer driver
lib/core/storage    repository-shaped persistence
lib/core/state      Riverpod controllers for settings, peers, transfers, network, updates
lib/core/update     GitHub Releases client and platform asset selection
lib/features        Devices, pairing, send, receive, transfers, settings UI
```

## Security model

- Every device generates a self-signed P-256 certificate on first run.
- The QR code carries the LAN address, port, a single-use 6-digit PIN, and the
  certificate's SHA-256 fingerprint.
- The sender verifies the certificate fingerprint during the TLS handshake
  (TOFU) and pins it for later transfers; a changed fingerprint blocks the
  connection.
- A session token is issued after pairing and required on every API call.
- For request/approve pairing, the receiver pins the fingerprint observed from
  the TLS connection (or a validated header) and displays it on the approval
  prompt. The sender re-verifies the receiver's fingerprint before accepting
  the returned token. No token exists until a human taps **Approve**.
- Every incoming transfer must be explicitly accepted. Paths are canonicalised
  and constrained to a staging directory; checksums are verified before files
  are promoted to the download folder.

## M3 Expressive fidelity

- **Typography:** the exact baseline scale (sizes, line heights, tracking and
  weights) is applied from `tokens.md`. Emphasized styles are **opt-in**, not a
  global override — used for selection, the FAB label, primary buttons, badges
  and status chips (`WiEmphasis` theme extension, `context.emphasizedText`).
- **Shape:** the 10-step radius scale lives in `WiRadius`; `inner = outer −
  padding` is enforced. Per-component geometry comes from the Compose M3
  tokens: cards 12dp, snackbar and outlined text fields 4dp, dialogs and bottom
  sheets 28dp, medium FAB 80dp with a 28dp icon, progress track 4dp with a 4dp
  stop indicator.
- **Colour:** body `surface`, navigation `surface container`, FAB `primary
  container` / `on primary container`, selected nav `secondary container` /
  `secondary`, badges `error` / `on error`, dividers `outline variant`,
  snackbars `inverse surface` / `inverse on surface`.
- **Motion:** expressive springs from the M3 token table are mapped to Flutter's
  `SpringSimulation` (Flutter has no motion physics library — my design
  decision). Spatial springs drive geometry; effects springs (damping 1.0)
  drive opacity and never overshoot. There are exactly **two hero moments**:
  the first peer appearing in Send, and the first completed transfer. No
  stagger or choreography timings are invented.
- **Transitions and RTL:** top-level destinations use the M3 top-level quick
  fade with the published legacy tokens — 400ms emphasized decelerate on
  enter, 200ms emphasized accelerate on exit. The incoming screen fades in
  only after the outgoing one has gone (my design decision to avoid Flutter's
  cross-fade); pushed pages use the platform's forward/backward default. Under
  reduced motion a subtle 100ms fade replaces hard cuts, while spring reveals
  and shape morphing stay disabled. Directional icons such as Send mirror in
  RTL; non-directional icons never do.
- **Golden tests:** `test/golden_test.dart` snapshots the theme showcase in
  light, dark and high contrast. Regenerate with
  `flutter test --update-goldens test/golden_test.dart`.
- **Loading indicator:** M3's seven-shape morphing indicator (48dp container,
  38dp active indicator) is implemented in `WiLoadingIndicator` with spring
  segments and no morphing under reduced motion. Flutter has no `MaterialShapes`
  library, so the seven silhouettes are a labelled approximation (my design
  decision), not the official vector paths.
- **Flutter gaps:** emphasized type, motion physics and contrast levels have no
  Flutter library support; they are implemented from published token values and
  labelled as design decisions in code and in the plan file.
- **Update manager:** from M3 — a small 6dp / 3dp-radius badge marks the
  unread "update available" state; "Check now" and Download use emphasized
  `label large` (primary actions), icons are 20dp, dialogs use 28dp corners,
  and the check indicator uses the loading indicator at 24dp (inside M3's
  24–240dp flexible range). My design decisions (not in M3): GitHub Releases
  as the source, a 10s timeout, a 15-minute passive cache, Android's
  DownloadManager for APKs (browser on desktop, no in-app installer), and a
  240dp cap on release notes. The passive check never shows a dialog and no
  third hero moment was added.

See the token tests (`test/theme_test.dart`, `test/widget_test.dart`) which
assert the published values rather than approximations.
