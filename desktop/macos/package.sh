#!/bin/sh
# Builds fx-desktop.app and fx-desktop-macos-arm64.dmg in
# desktop/zig-out/package, plus the update zip and a manifest naming its
# version and sha256.
#
#   VERSION=0.0.18 sh macos/package.sh
#
# Signs with $CODESIGN_IDENTITY (a "Developer ID Application" identity in the
# keychain) when set, else ad hoc. Notarizes and staples the app and the disk
# image when it is set and either NOTARY_PROFILE (a profile saved with
# `xcrun notarytool store-credentials`) or NOTARY_KEY_PATH, NOTARY_KEY_ID and
# NOTARY_ISSUER_ID (an App Store Connect API key) are set.
set -eu
cd "$(dirname "$0")/.."

app=fx-desktop
version="${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.0.0)}"
version="${version#v}"
out=zig-out/package
bundle="$out/$app.app"
dmg="$out/$app-macos-arm64.dmg"
zip="$out/$app-macos-arm64.zip"

# macOS 13 and Apple silicon from the M1 on: a native build would need the
# macOS and the CPU it was built on.
min_macos=13.0
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos.$min_macos -Dcpu=apple_m1 \
  -Dversion="$version" ${ZIG_FLAGS:-}
if ! vtool -show-build "zig-out/bin/$app" | grep -q "minos $min_macos\$"; then
  echo "zig-out/bin/$app is not built for macOS $min_macos:" >&2
  vtool -show-build "zig-out/bin/$app" >&2
  exit 1
fi
rm -rf "$out"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "zig-out/bin/$app" "$bundle/Contents/MacOS/$app"
cp macos/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>fx</string>
  <key>CFBundleDisplayName</key><string>fx</string>
  <key>CFBundleIdentifier</key><string>app.perch.fx-desktop</string>
  <key>CFBundleExecutable</key><string>$app</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleGetInfoString</key><string>A native desktop for fx</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>$min_macos</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

sign() {
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$1"
  else
    codesign --force --sign - "$1"
  fi
}

notarizing() {
  [ -n "${CODESIGN_IDENTITY:-}" ] && { [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${NOTARY_KEY_PATH:-}" ]; }
}

notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" --wait
  fi
}

sign "$bundle"
if notarizing; then
  ditto -c -k --keepParent "$bundle" "$out/$app.zip"
  notarize "$out/$app.zip"
  xcrun stapler staple "$bundle"
  rm "$out/$app.zip"
fi

# The disk image: the app, and Applications to drag it to.
stage="$out/dmg"
mkdir -p "$stage"
cp -R "$bundle" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "fx" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$stage"
sign "$dmg"
if notarizing; then
  notarize "$dmg"
  xcrun stapler staple "$dmg"
fi
shasum -a 256 "$dmg" | tee "$dmg.sha256"

# The update: the (stapled) app zipped, and a manifest naming its version and
# the zip's sha256. Kept in the same shape as nanoterm's tools/manifest.sh.
ditto -c -k --keepParent "$bundle" "$zip"
zip_sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
cat > "$out/manifest.json" <<MANIFEST
{
  "version": "$version",
  "url": "$app-macos-arm64.zip",
  "sha256": "$zip_sha"
}
MANIFEST
cat "$out/manifest.json"
