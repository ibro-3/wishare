# Changelog

## v0.2.0 — navigation and motion

- History and Settings are now pushed above the shell instead of replacing it;
  the system/AppBar back button returns to the Send or Receive tab you came
  from. Pairing and scanning use the same push/pop flow, including the inline
  Pair action on a nearby device.
- History now has its own app bar (it had none), Settings owns its scaffold,
  and both tabs keep their scroll position when switching destinations.
- Top-level tab changes use the M3 quick-fade tokens: 400ms emphasized
  decelerate on enter, 200ms emphasized accelerate on exit, with the incoming
  screen fading in only after the outgoing one has gone (no cross-fade).
  Pushed pages use the platform's forward/backward default transition.
- Reduced motion now uses a subtle 100ms fade instead of a hard cut; spring
  reveals and the morphing loading indicator stay disabled.
- Added the second hero moment: the first peer appearing in the Send device
  list, animated once per session with the fast spatial/effects springs.
- Full-page loading states consistently use the M3 loading indicator.
- Keyboard shortcut `Ctrl/⌘+4` opens Settings; `3` opens History.

## v0.1.3 — single device list

- Send to is now the single device list: paired devices stay on top and send
  on tap, while nearby devices appear in the same list with an inline Pair
  button. The separate Nearby devices section was removed.

## v0.1.2 — navigation and reachability

- History and Settings moved to the app bar's trailing edge; pairing moved
  out of the app bar into an extended FAB labelled "Pair" at the bottom
  trailing corner.
- Send and Receive moved from the top tab bar to a bottom navigation bar so
  both destinations stay within thumb reach.
- Fixed an inherited-widget error on first mount: Send and Scan now receive
  their route parameters through constructors instead of calling
  `GoRouterState.of(context)` from `initState`.
- The Send tab no longer has a separate Send button: paired devices are listed
  and tapping one sends the selected files or folders.

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
