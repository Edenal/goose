#!/bin/sh
# Build build/GOOSE.app: binary + bundled SDL3 + shaders/assets + icon, ad-hoc signed.
set -e
cd "$(dirname "$0")/.."
APP=build/GOOSE.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/assets/gen" "$APP/Contents/Frameworks"
cp build/goose-release "$APP/Contents/MacOS/goose"
cp tools/Info.plist "$APP/Contents/Info.plist"
cp -R shaders "$APP/Contents/Resources/shaders"
cp assets/gen/*.png "$APP/Contents/Resources/assets/gen/"
cp assets/OLDSCHOOL-PC-FONTS-LICENSE.TXT LICENSE README.md "$APP/Contents/Resources/"
# SDL3 (universal, macOS 12+, install name @rpath/libSDL3.0.dylib; the binary's rpath points at Frameworks)
cp build/sdl3/lib/libSDL3.0.dylib "$APP/Contents/Frameworks/libSDL3.0.dylib"
# icon from the ESA cube
ICON=build/goose.iconset
rm -rf "$ICON"; mkdir -p "$ICON"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s assets/gen/logo_cube.png --out "$ICON/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -s format png -z $d $d assets/gen/logo_cube.png --out "$ICON/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON" -o "$APP/Contents/Resources/goose.icns"
rm -rf "$ICON"
codesign --force --deep -s - "$APP" 2>/dev/null
echo "built $APP"
