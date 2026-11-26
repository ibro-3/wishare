# Changelog

## v0.1.1 — bug fixes and cleanup

Interface

- Two primary tabs, Send and Receive, replace the bottom navigation bar and
  desktop rail on all screen sizes.
- History sits immediately left of Settings in the app-bar leading area;
  pair/QR remains the single trailing action.
- Incoming offers are handled only inside the Receive tab, with a pending
  badge on the tab; the automatic bottom sheet was removed.
- Nearby/unpaired devices are listed in the Send tab with a Pair action.
- Dark theme now uses the correct text colour roles, so body text stays
  legible; reduced-motion is read from the platform setting and honoured by
  page transitions, spring reveals and the loading indicator.
- RTL directional icons are mirrored horizontally rather than rotated.
- Progress indicators and the pairing QR code carry semantics labels.

Fixes

- A device paired from the Send side is now correctly treated as paired, so
  the Send button becomes available.
- Receiver pairing stores the sender's certificate fingerprint instead of
  pinning the receiver's own identity.
- Settings changes no longer tear down the HTTPS server and discovery service
  mid-transfer.
- `POST /cancel` now requires a paired token and verifies the sender identity.
- Transfer IDs are validated before being used as filesystem paths; malformed
  pairing QR codes and short fingerprints no longer crash the UI.
- Chunk writes are serialized per transfer, so concurrent chunks cannot corrupt
  a file or double-count progress.
- Finalizing a transfer falls back to copy-then-delete across filesystems and
  keeps partially received files out of the download folder on failure.
- Declined and cancelled transfers are reported explicitly to the sender, and
  failed outgoing transfers are recorded in History instead of staying Active.
- Corrupt preferences, stale enum values and hostile UDP announcements no
  longer break startup or discovery.
- Notifications use a unique ID per transfer; multiple queued share intents
  are no longer overwritten.

Release workflow

- Builds and attaches split APKs for `arm64-v8a`, `armeabi-v7a` and `x86_64`,
  alongside the universal APK.

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
- `wishare-0.1.0-android.apk` — universal Android release APK
- `wishare-0.1.0-android-arm64-v8a.apk`, `-armeabi-v7a.apk`, `-x86_64.apk` —
  per-ABI Android release APKs
- `SHA256SUMS.txt` — checksums for all assets

Notes

- Android local release builds use the debug key unless the
  `WISHARE_KEYSTORE_*` environment variables are supplied.
- Windows assets are produced by CI on a Windows runner.
