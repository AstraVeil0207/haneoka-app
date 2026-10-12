#!/bin/bash
set -euo pipefail
bundle=$1
version=$2
architecture=$3
destination=$4
case "$architecture" in
  x64) slice=x86_64 ;;
  arm64) slice=arm64 ;;
  *) exit 2 ;;
esac
name="haneoka-macos-$architecture"
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/app" "$stage/pkg/Applications" "$stage/dmg"
ditto "$bundle" "$stage/app/haneoka.app"
app="$stage/app/haneoka.app"
# Thin every native image, including frameworks and bundled ADB, before signing.
while IFS= read -r -d '' native; do
  if file -b "$native" | grep -q 'Mach-O'; then
    lipo "$native" -verify_arch "$slice"
    arches=$(lipo -archs "$native")
    if [[ "$arches" == *" "* ]]; then
      lipo "$native" -thin "$slice" -output "$native.thin"
      mv "$native.thin" "$native"
      chmod 755 "$native"
    fi
  fi
done < <(find "$app" -type f -print0)
[[ "$(lipo -archs "$app/Contents/MacOS/haneoka")" == "$slice" ]]
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto "$app" "$stage/pkg/Applications/haneoka.app"
ditto "$app" "$stage/dmg/haneoka.app"
ln -s /Applications "$stage/dmg/Applications"
ditto -c -k --keepParent "$app" "$destination/$name.zip"
hdiutil create -volname Haneoka -srcfolder "$stage/dmg" -ov -format UDZO "$destination/$name.dmg"
pkgbuild --root "$stage/pkg" --identifier org.haneoka.haneoka --version "$version" \
  --install-location / "$destination/$name.pkg"
