#!/bin/zsh
# Empaqueta AuraNotch.app (release) con firma ad-hoc. Sin Xcode: sin notarización (ver ADR 0001).
# Uso: Scripts/package-app.sh [salida]   (por defecto ./dist/AuraNotch.app)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/AuraNotch.app}"
ARCHS=(--arch arm64 --arch x86_64) # binario universal
swift build -c release --product AuraNotch ${ARCHS[@]}
BIN="$(swift build -c release --product AuraNotch ${ARCHS[@]} --show-bin-path)/AuraNotch"
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/AuraNotch"
cp Scripts/Info.plist "$OUT/Contents/Info.plist"
cp -R Resources/*.lproj "$OUT/Contents/Resources/"
[ -f Assets/AppIcon.icns ] && cp Assets/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
plutil -lint "$OUT/Contents/Info.plist" >/dev/null
codesign --force --sign - "$OUT"
codesign --verify --verbose=1 "$OUT"
echo "Listo: $OUT (firma ad-hoc; Gatekeeper pedirá abrirla con clic derecho)"
