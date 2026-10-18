#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/dist/ShiftDrop.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/ShiftDrop "$app/Contents/MacOS/ShiftDrop"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
webp_prefix=""
for candidate in /opt/homebrew/opt/webp /usr/local/opt/webp; do
    if [ -f "$candidate/lib/libwebp.dylib" ]; then webp_prefix="$candidate"; break; fi
done
if [ -z "$webp_prefix" ]; then
    echo "WebP is required to package all formats. Install it with: brew install webp" >&2
    exit 1
fi
cp -L "$webp_prefix/lib/libwebp.dylib" "$app/Contents/Frameworks/libwebp.dylib"
cp -L "$webp_prefix/lib/libsharpyuv.dylib" "$app/Contents/Frameworks/libsharpyuv.0.dylib"
chmod u+w "$app/Contents/Frameworks/"*.dylib
install_name_tool -id @loader_path/libwebp.dylib "$app/Contents/Frameworks/libwebp.dylib"
install_name_tool -change @rpath/libsharpyuv.0.dylib @loader_path/libsharpyuv.0.dylib "$app/Contents/Frameworks/libwebp.dylib"
install_name_tool -id @loader_path/libsharpyuv.0.dylib "$app/Contents/Frameworks/libsharpyuv.0.dylib"
cp "$webp_prefix/COPYING" "$app/Contents/Resources/WebP-LICENSE.txt"
# Finder's folder metadata is not permitted in a signed application bundle.
xattr -cr "$app"
codesign --force --sign - "$app/Contents/Frameworks/libsharpyuv.0.dylib"
codesign --force --sign - "$app/Contents/Frameworks/libwebp.dylib"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app"
