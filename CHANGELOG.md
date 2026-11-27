# Changelog

## v0.5.0 — everyday sharing

- Desktop drag-and-drop on the Send tab: files and folders can be dropped
  anywhere on the page and are expanded with the same depth/file limits as the
  pickers. A translucent primary-container overlay confirms the drop target.
- Completed incoming transfers now offer **Open folder** and, for a single
  file, **Open file**. Android opens files through a FileProvider-backed
  ACTION_VIEW intent; Linux and Windows use xdg-open and explorer.
- Transfer progress shows the measured rate and an estimated time remaining in
  the Send tab, the Receive tab and History details.
- History is now a top-level destination beside Send and Receive (three
  destinations, inside M3's guidance), with All / Sent / Received filters. The
  selected filter uses emphasized type.
- At widths of 600dp and above the bottom bar becomes a navigation rail; the
  color roles and destinations are unchanged. The Pair FAB stays available.
- Accessibility: device rows expose pairing state and address, progress is a
  live region with byte counts, and automated tap-target/contrast guideline
  tests cover Send, Receive and History. The full screen-reader audit remains
  outstanding.

## v0.4.1 — nearby scan and pairing reliability

- Discovery now binds its UDP heartbeat, mDNS querier and mDNS responder to the
  same LAN address used for QR pairing. On machines with a VPN or several
  adapters, heartbeats and mDNS queries no longer leave through the default
  route, which was a common reason nearby devices never appeared.
- Added a **Scan again** action to the Send tab with a scanning indicator and
  last-scan time. Discovery start/stop is now idempotent and settings toggles
  restart it cleanly without leaking sockets or the Android multicast lock.
- The mDNS responder now publishes an A record for its SRV target as well as
  the instance name, so standard DNS-SD browsers can resolve Wishare services.
  Cached mDNS records can no longer keep a device that left the network in the
  nearby list.
- Pairing polls survive transient network errors (including a not-yet-created
  request) and can be cancelled from the Send tab while waiting for approval.
  Devices discovered without a verifiable fingerprint now explain how to pair
  by QR or manual entry instead of failing with a cryptic error. Manual entry
  rejects loopback, link-local and non-LAN addresses before connecting.

## v0.4.0 — discovery and pairing fixes

- Enabled IPv4 broadcast on the discovery socket and send heartbeats to each
  interface's broadcast address. Previously Dart's default disabled broadcast
  and the resulting socket error was swallowed, so nearby devices never saw
  each other and request/approve pairing could not start.
- Added an mDNS querier alongside the existing responder, with an Android Wi-Fi
  multicast lock, so discovery has a second path on networks that block UDP
  broadcast. Fixed a malformed SRV record (missing weight field) that prevented
  standards-based mDNS browsers from resolving Wishare services.
- Desktop pairing no longer opens a camera page that has no plugin: Linux and
  Windows go straight to manual IP/PIN/fingerprint entry, while **Show my code**
  remains available. Camera failures on supported platforms now offer the same
  fallback.
- Pairing QR codes use a real LAN address instead of the first non-loopback
  interface, which could be a Docker or VPN address. Discovery failures are
  now shown on the Send tab instead of being silent.

## v0.3.2 — Android update downloads

- On Android, update APKs are enqueued in the system DownloadManager instead of
  opening a browser. The download continues in the background, posts a
  completion notification and appears in the Downloads app. A snackbar confirms
  the download started. Desktop keeps the browser path; release-page fallbacks
  are unchanged.
- File names passed to DownloadManager are reduced to a safe basename so query
  strings and path segments cannot escape the Downloads directory.

## v0.3.1 — pairing without a QR code

- Fixed the pairing dead end: the screen that generates the QR code had no
  UI entry point. The scanner now has a "Show my code" action that opens it,
  and the two screens are titled "Scan pairing code" and "Show pairing code"
  so it is clear which device does which.
- Added request/approve pairing for nearby devices: tap **Pair** on a nearby
  device in Send and the receiver gets a dialog with the observed certificate
  fingerprint plus **Approve** / **Decline**. No QR code and no PIN are typed
  anywhere. A session token is issued only on approval; requests expire after
  two minutes and are bounded to eight pending entries.
- Manual IP/PIN/fingerprint entry remains available from the scanner's keyboard
  button as a fallback.

## v0.3.0 — update manager

- Added an update manager backed by the GitHub Releases API. A passive check
  runs once on startup (cached for 15 minutes) and only raises a small badge
  on the Settings icon — it never interrupts the user. Settings has a new
  "Updates" card with a manual "Check now" action, release notes and a
  platform-aware Download button; when no matching build exists it opens the
  release page instead.
- "Check on startup" is a Settings toggle, default on, so the app's single
  outbound internet call can be disabled. Manual checks always work.
- Manual check results use an M3 snackbar: "up to date" auto-dismisses, a
  failure offers Retry. An available update opens a 28dp dialog with the
  release notes and a filled Download action beside a text "Later" action.
  No new hero moments or hand-authored springs were added.
- Version `0.3.0` is now a single Dart constant used by the Settings footer
  and the update comparison; a test asserts it matches `pubspec.yaml`.

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
