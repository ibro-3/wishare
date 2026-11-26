# Packaging templates

These are starting points, not verified builds in this environment.

## Linux (.desktop / Flatpak)

`wishare.desktop` installs the launcher entry; the hicolor icon is already
copied into the release bundle by `linux/CMakeLists.txt`.

```bash
flutter build linux --release
cp packaging/wishare.desktop ~/.local/share/applications/
flatpak-builder --user --install build-dir packaging/flatpak/wishare.yml
```

The Flatpak manifest assumes a prebuilt release bundle. A fully sandboxed
Flutter build needs the Flutter SDK as an additional module.

## Debian (.deb)

Use `fpm` (or equivalent) over `build/linux/x64/release/bundle`:

```bash
fpm -s dir -t deb -n wishare -v 0.1.1 \
  --prefix /opt/wishare \
  -C build/linux/x64/release/bundle . \
  --desktop-entry packaging/wishare.desktop
```

## Windows (MSIX)

`msix_config.yaml` is a template for the `msix` package. Add it as a dev
dependency, replace the placeholder publisher/CN, supply a signing
certificate, then:

```bash
flutter build windows --release
flutter pub run msix:create --config packaging/msix_config.yaml
```

## Android (Play)

Release signing reads `WISHARE_KEYSTORE_PATH`, `WISHARE_STORE_PASSWORD`,
`WISHARE_KEY_ALIAS` and `WISHARE_KEY_PASSWORD`. Without them, local release
builds use the debug key. Use `flutter build appbundle --release` for upload.
