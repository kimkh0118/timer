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
cp -R "$ROOT/app/Resources/." "$APP/Contents/Resources/"
xcrun swiftc -O -target arm64-apple-macos11.0 "$ROOT/src/main.swift" -o "$APP/Contents/MacOS/Timer" -framework Cocoa -framework WebKit
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
echo "✓ 완료: $APP"

if [ "${1:-}" = "--package" ]; then
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
