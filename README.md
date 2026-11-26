# Wishare

LAN-only peer-to-peer file and folder sharing for **Linux, Android and Windows**,
built with Flutter and designed with Material 3 Expressive tokens.

No account, no cloud, no relay: devices on the same network discover each other,
pair once with a QR code (certificate fingerprint + PIN), then exchange files
directly over HTTPS with resumable chunks and SHA-256 verification.

## Current status (v0.1.3)

Implemented:

- M3 Expressive theme layer: exact radius scale, emphasized type built from
  published tokens, colour-role mapping, dynamic colour with static baseline
  fallback, contrast levels, and spring values mapped to Flutter's
  `SpringSimulation`.
- Adaptive shell: Send and Receive in a bottom navigation bar on every screen
  size, with History and Settings in the app bar's trailing edge and pairing
  in an extended FAB above the bar. Send to lists every known device with
  paired ones on top: pick files or a folder and tap a paired device to send,
  or use the inline Pair button for nearby devices. Bottom sheets on phones,
  dialogs on desktop.
- Device discovery via a DNS-SD mDNS responder (`_wishare._tcp.local`) plus a
  UDP broadcast heartbeat, with manual IP/QR fallback.
- Self-signed P-256 certificate generation and TOFU fingerprint pinning.
- QR pairing and manual pairing with PIN + displayed fingerprint confirmation.
- HTTPS receiver and sender: pairing token, transfer offers, chunk streaming
  with resume, checksum verification, safe folder extraction, transfer history.
- Android foreground service declaration, Wi-Fi lock and "Share to Wishare"
  intent intake; desktop window setup with a tray icon and menu.
- Persistent peers, transfers and settings via `shared_preferences` + JSON.

Still out of scope for v0.1:

- Packaged installers/signing (release CI attaches zips and APKs; MSIX and deb
  packaging templates live in `packaging/`).
- A full manual accessibility audit (semantics are in place, but not audited
  on screen readers).

## Run

```bash
flutter pub get
flutter run -d linux        # or -d android / -d windows (Windows host required)
```

Release builds:

```bash
flutter build apk --release     # uses debug key unless WISHARE_KEYSTORE_PATH,
                                # WISHARE_STORE_PASSWORD, WISHARE_KEY_ALIAS and
                                # WISHARE_KEY_PASSWORD are set
flutter build linux --release
# flutter build windows --release  (Windows host required)
```

Publishing a GitHub release (v0.1.3):

```bash
git tag v0.1.3 && git push origin v0.1.3
```

`.github/workflows/release.yml` builds Windows, Linux and Android in parallel,
then attaches `wishare-0.1.3-windows-x64.zip`, `wishare-0.1.3-linux-x64.zip`,
`wishare-0.1.3-android.apk`, the three per-ABI APKs and `SHA256SUMS.txt` to the
release. The workflow can also be started manually with `workflow_dispatch` and
a tag name. `dist/` holds the older local assets; v0.1.3 assets are produced by
CI when the tag is pushed.

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
lib/core/state      Riverpod controllers for settings, peers, transfers, network
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
  the first peer appearing, and the first completed transfer. No stagger or
  choreography timings are invented.
- **Transitions and RTL:** top-level destinations use the M3 top-level pattern
  (quick fade, emphasized decelerate on enter / accelerate on exit, legacy
  duration tokens because M3 transitions still use them). Directional icons
  such as Send mirror in RTL; non-directional icons never do.
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

See the token tests (`test/theme_test.dart`, `test/widget_test.dart`) which
assert the published values rather than approximations.
