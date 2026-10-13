#!/bin/sh
set -eu
export PATH="$HOME/.cargo/bin:$PATH"
ROOT=$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)
CARGO_TARGET_DIR="$ROOT/build/rust-apple/$PLATFORM_NAME"
export CARGO_TARGET_DIR
for ARCH in $ARCHS; do
  case "$PLATFORM_NAME:$ARCH" in
    macosx:arm64) TRIPLE=aarch64-apple-darwin ;;
    macosx:x86_64) TRIPLE=x86_64-apple-darwin ;;
    iphoneos:arm64) TRIPLE=aarch64-apple-ios ;;
    iphonesimulator:arm64) TRIPLE=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) TRIPLE=x86_64-apple-ios ;;
    *) echo "Unsupported Rust architecture: $PLATFORM_NAME:$ARCH" >&2; exit 1 ;;
  esac
  cargo build --release --locked --manifest-path "$ROOT/native/team_engine/Cargo.toml" --target "$TRIPLE"

done
if [ "$PLATFORM_NAME" = macosx ]; then
  DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/libhaneoka_team_engine.dylib"
else
  DEST="$BUILT_PRODUCTS_DIR/libhaneoka_team_engine.a"
fi
mkdir -p "$(dirname "$DEST")"
# Cargo outputs contain no whitespace; the project path can, so construct
# the lipo arguments again rather than splitting filesystem paths.
set --
for ARCH in $ARCHS; do
  case "$PLATFORM_NAME:$ARCH" in
    macosx:arm64) TRIPLE=aarch64-apple-darwin ;;
    macosx:x86_64) TRIPLE=x86_64-apple-darwin ;;
    iphoneos:arm64) TRIPLE=aarch64-apple-ios ;;
    iphonesimulator:arm64) TRIPLE=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) TRIPLE=x86_64-apple-ios ;;
  esac
  if [ "$PLATFORM_NAME" = macosx ]; then EXT=dylib; else EXT=a; fi
  set -- "$@" "$CARGO_TARGET_DIR/$TRIPLE/release/libhaneoka_team_engine.$EXT"
done
xcrun lipo -create "$@" -output "$DEST"
if [ "$PLATFORM_NAME" = macosx ]; then
  install_name_tool -id '@rpath/libhaneoka_team_engine.dylib' "$DEST"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST"
  fi
fi
