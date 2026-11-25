# Changelog

## Unreleased — navigation redesign

- Two primary tabs, Send and Receive, replace the bottom navigation bar and
  desktop rail on all screen sizes.
- History button sits immediately left of the Settings icon in the app-bar
  leading area; pair/QR remains the single trailing action.
- Incoming offers are handled only inside the Receive tab, with a pending badge
  on the tab; the automatic bottom sheet was removed.
- Nearby/unpaired devices are listed in the Send tab with a Pair action.

## v0.1.0 — first local-network release

Features

- LAN-only peer-to-peer sending of multiple files and recursive folders.
- Discovery via mDNS (`_wishare._tcp.local`), UDP broadcast heartbeat, manual
  IP entry and QR pairing.
- Self-signed P-256 TLS certificates with TOFU fingerprint pinning; single-use
  PIN pairing with a manual fallback.
- Chunked, resumable transfers with SHA-256 verification and safe folder
  extraction.
- Explicit accept/decline for incoming transfers, cancellation, progress,
  speed, history and detail views.
- Transfer notifications when the app is backgrounded.
- Android "Share to Wishare" intake and foreground receiver service.
- Desktop tray with close-to-tray, window-size persistence, keyboard shortcuts
  and single-instance handling on Windows.
- Material 3 Expressive theming: exact type/shape/colour tokens, opt-in
  emphasized type, spring-driven hero moments, loading indicator, RTL mirroring
  and contrast levels.
- Android share-intent intake and platform launcher icons.

Assets published by the release workflow

- `wishare-0.1.0-windows-x64.zip` — Windows release bundle (executable + data)
- `wishare-0.1.0-linux-x64.zip` — Linux release bundle
- `wishare-0.1.0-android.apk` — Android release APK
- `SHA256SUMS.txt` — checksums for all assets

Notes

- Android local release builds use the debug key unless the
  `WISHARE_KEYSTORE_*` environment variables are supplied.
- Windows assets are produced by CI on a Windows runner.
