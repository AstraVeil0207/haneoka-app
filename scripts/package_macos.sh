#!/bin/bash
set -euo pipefail
bundle=$1
version=$2
destination=$3
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pkg/Applications" "$stage/dmg"
ditto "$bundle" "$stage/pkg/Applications/haneoka.app"
ditto "$bundle" "$stage/dmg/haneoka.app"
ln -s /Applications "$stage/dmg/Applications"
ditto -c -k --keepParent "$bundle" "$destination/haneoka-macos.zip"
hdiutil create -volname Haneoka -srcfolder "$stage/dmg" -ov -format UDZO "$destination/haneoka-macos.dmg"
pkgbuild --root "$stage/pkg" --identifier org.haneoka.haneoka --version "$version" \
  --install-location / "$destination/haneoka-macos.pkg"
