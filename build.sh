#!/bin/bash
# 타이머 앱 빌드
#   ./build.sh            → build/타이머.app 만들기
#   ./build.sh --install  → 바탕화면에 설치하고 실행
#   ./build.sh --package  → 배포용 build/Timer.dmg 및 Timer.zip 만들기
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="타이머"
APP="$ROOT/build/$NAME.app"

xcrun --find swiftc >/dev/null 2>&1 || { echo "swiftc가 없어요. 'xcode-select --install'로 설치하세요." >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
# 원본 MP3는 저장소에만 두고, 앱에는 실제로 쓰는 파일만 넣어요.
rsync -a --exclude '*.mp3' --exclude '.DS_Store' "$ROOT/app/Resources/" "$APP/Contents/Resources/"
cp "$ROOT/app/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 엔딩 크레딧에 들어갈 숫자(커밋 수·버전 수)를 빌드할 때 넣어요.
COMMITS="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
VERSIONS="$(git -C "$ROOT" tag 2>/dev/null | wc -l | tr -d ' ')"
echo "window.CREDIT_STATS = { commits: $COMMITS, versions: $((VERSIONS + 1)) };" > "$APP/Contents/Resources/credits-stats.js"

# Apple Silicon + Intel 둘 다 돌아가는 유니버설 앱으로 만들어요.
TMP_BIN="$(mktemp -d)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -target "$ARCH-apple-macos11.0" "$ROOT/src/main.swift" -o "$TMP_BIN/Timer-$ARCH" -framework Cocoa -framework WebKit
done
lipo -create "$TMP_BIN/Timer-arm64" "$TMP_BIN/Timer-x86_64" -output "$APP/Contents/MacOS/Timer"
rm -rf "$TMP_BIN"
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
echo "✓ 완료: $APP"

if [ "${1:-}" = "--package" ]; then
  rm -f "$ROOT/build/Timer.zip" "$ROOT/build/Timer.dmg"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/Timer.zip"
  DMG_STAGE="$(mktemp -d "$ROOT/build/dmg.XXXXXX")"
  ditto "$APP" "$DMG_STAGE/$NAME.app"
  ln -s /Applications "$DMG_STAGE/Applications"
  cp "$ROOT/app/INSTALL.txt" "$DMG_STAGE/설치 안내.txt"
  hdiutil create -volname "타이머 설치" -srcfolder "$DMG_STAGE" -ov -format UDZO "$ROOT/build/Timer.dmg"
  rm -rf "$DMG_STAGE"
  echo "✓ 배포 파일: $ROOT/build/Timer.dmg, $ROOT/build/Timer.zip"
fi

if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Desktop/$NAME.app"
  pkill -x Timer 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"; cp -R "$APP" "$DEST"
  open "$DEST"
  echo "✓ $DEST 에 설치하고 실행했어요"
fi
