#!/bin/bash
# 타이머 한 줄 설치
#   curl -fsSL https://raw.githubusercontent.com/kimkh0118/timer/main/install.sh | bash
# 지우기
#   curl -fsSL https://raw.githubusercontent.com/kimkh0118/timer/main/install.sh | bash -s -- --uninstall
set -euo pipefail

NAME="타이머"
URL="${TIMER_URL:-https://github.com/kimkh0118/timer/releases/latest/download/Timer.zip}"

say()  { printf "\033[1;31m●\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m✕ %s\033[0m\n" "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "맥(macOS)에서만 설치할 수 있어요."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 11 ] || fail "macOS 11(Big Sur) 이상이 필요해요."

# 응용 프로그램 폴더에 쓸 수 있으면 거기에, 아니면 내 계정의 응용 프로그램 폴더에
if [ -n "${TIMER_DIR:-}" ]; then DIR="$TIMER_DIR"; mkdir -p "$DIR"; elif [ -w /Applications ]; then DIR="/Applications"; else DIR="$HOME/Applications"; mkdir -p "$DIR"; fi
DEST="$DIR/$NAME.app"

if [ "${1:-}" = "--uninstall" ]; then
  pkill -x Timer 2>/dev/null || true
  rm -rf "/Applications/$NAME.app" "$HOME/Applications/$NAME.app"
  say "타이머를 지웠어요."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "최신 버전을 받는 중..."
curl -fL --progress-bar "$URL" -o "$TMP/Timer.zip" || fail "다운로드하지 못했어요. 인터넷 연결을 확인해 주세요."
ditto -x -k "$TMP/Timer.zip" "$TMP/out" || fail "압축을 풀지 못했어요."
[ -d "$TMP/out/$NAME.app" ] || fail "받은 파일에 앱이 없어요."

say "설치하는 중..."
pkill -x Timer 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$TMP/out/$NAME.app" "$DEST"
# 직접 받은 앱이라 "확인되지 않은 개발자" 경고가 뜨지 않게 다운로드 표시를 지워요.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

VER="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
say "설치 완료! ($DEST, 버전 $VER)"
open "$DEST"
