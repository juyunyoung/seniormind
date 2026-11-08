#!/usr/bin/env bash
# 연결할 백엔드를 바꾼다(Mac). Local.xcconfig·Firebase plist를 맞추고 Xcode 프로젝트를 다시 만든다.
#
#   "$HOME/seniormind/app/ios/scripts/switch_backend.sh" seniormind  # 내 백엔드(기본)
#   "$HOME/seniormind/app/ios/scripts/switch_backend.sh" team      # 이현님 팀 서버
#   "$HOME/seniormind/app/ios/scripts/switch_backend.sh" mock      # 서버 없이 화면만(목 모드)
#   "$HOME/seniormind/app/ios/scripts/switch_backend.sh" <이름>    # Local.xcconfig에 정의한 다른 백엔드
#
# 옵션(처음 한 번, 값은 Local.xcconfig에 저장)
#   --plist <파일>     받은 GoogleService-Info.plist를 이 백엔드용으로 복사(번들 ID·프로젝트 ID 확인 후)
#   --url <주소>       서버 주소. 예: https://<서비스>.run.app
#   --bundle <ID>      Firebase에 등록한 iOS 번들 ID   (team 외 백엔드)
#   --project <ID>     Firebase 프로젝트 ID            (team 외 백엔드)
#   --no-open          끝나고 Xcode를 열지 않음
#
# Local.xcconfig·plist는 저장소에 올리지 않는다(.gitignore). 개인 백엔드 정보는 Local.xcconfig에만 둔다.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$IOS_DIR/Config/Base.xcconfig"
LOCAL="$IOS_DIR/Config/Local.xcconfig"
FIREBASE_DIR="$IOS_DIR/MemoryCapsule/Firebase"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 1 ] || usage
TARGET="$1"; shift
PLIST_SRC=""; URL=""; BUNDLE_ARG=""; PROJECT_ARG=""; OPEN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --plist)   PLIST_SRC="${2:-}"; shift 2 ;;
    --url)     URL="${2:-}"; shift 2 ;;
    --bundle)  BUNDLE_ARG="${2:-}"; shift 2 ;;
    --project) PROJECT_ARG="${2:-}"; shift 2 ;;
    --no-open) OPEN=0; shift ;;
    *) usage ;;
  esac
done
case "$TARGET" in
  mock) BACKEND=team; MOCK=YES ;;
  *) [[ "$TARGET" =~ ^[A-Za-z0-9]+$ ]] || { echo "! 백엔드 이름은 영문·숫자만 써요: $TARGET"; exit 1; }
     BACKEND="$TARGET"; MOCK=NO ;;
esac

[ -f "$LOCAL" ] || printf '// 개인 설정(저장소에 올리지 않음). scripts/switch_backend.sh가 값을 바꾼다.\nMC_DEVELOPMENT_TEAM =\n' > "$LOCAL"
get_key() {   # get_key KEY → Local.xcconfig 값, 없으면 Base.xcconfig 값
  local v
  v=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$LOCAL" 2>/dev/null | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//') || true
  [ -n "$v" ] || v=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$BASE" | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//') || true
  echo "$v"
}
set_key() {   # set_key KEY VALUE (Local.xcconfig에서 그 줄만 바꾸거나 추가)
  local tmp; tmp="$(mktemp)"
  awk -v k="$1" -v v="$2" 'BEGIN{done=0}
    $0 ~ "^[[:space:]]*"k"[[:space:]]*=" { if(!done){print k" = "v; done=1}; next }
    {print}
    END{ if(!done) print k" = "v }' "$LOCAL" > "$tmp" && mv "$tmp" "$LOCAL"
}
xc_url() { echo "$1" | sed -E 's#^https?://#https:/$()/#'; }   # xcconfig에서 // 가 주석이 되지 않게

# 1) 이 백엔드의 값 모으기(옵션으로 받은 값 우선)
BUNDLE="${BUNDLE_ARG:-$(get_key "MC_BUNDLE_ID_$BACKEND")}"
PROJECT="${PROJECT_ARG:-$(get_key "MC_FIREBASE_PROJECT_$BACKEND")}"
HAS_URL="$URL"; [ -n "$HAS_URL" ] || HAS_URL="$(get_key "MC_API_BASE_URL_$BACKEND")"
if [ "$MOCK" = NO ]; then
  missing=""
  [ -n "$HAS_URL" ] || missing="$missing --url"
  [ -n "$BUNDLE" ]  || missing="$missing --bundle"
  [ -n "$PROJECT" ] || missing="$missing --project"
  if [ -n "$missing" ]; then
    echo "! '$BACKEND' 백엔드 정보가 없어요. 처음 한 번 넣어 주세요:$missing"
    echo "  \"$0\" $BACKEND --url https://<서버>.run.app --bundle <번들 ID> --project <Firebase 프로젝트 ID> --plist <plist 파일>"
    exit 2
  fi
fi
PLIST_NAME="$(get_key "MC_FIREBASE_PLIST_$BACKEND")"; [ -n "$PLIST_NAME" ] || PLIST_NAME="GoogleService-Info-$BACKEND"
PLIST="$FIREBASE_DIR/$PLIST_NAME.plist"

# 2) Firebase plist 확인(맞지 않으면 아무것도 바꾸지 않고 멈춘다)
check_plist() {
  local b p
  b=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$1" 2>/dev/null || true)
  p=$(/usr/libexec/PlistBuddy -c "Print :PROJECT_ID" "$1" 2>/dev/null || true)
  if [ "$b" != "$BUNDLE" ] || [ "$p" != "$PROJECT" ]; then
    echo "! plist가 맞지 않아요: $1"
    echo "  들어 있는 값  번들=$b  프로젝트=$p"
    echo "  필요한 값     번들=$BUNDLE  프로젝트=$PROJECT"
    echo "  Firebase 콘솔: https://console.firebase.google.com/project/$PROJECT/settings/general"
    return 1
  fi
}
mkdir -p "$FIREBASE_DIR"
if [ "$MOCK" = NO ]; then
  if [ -n "$PLIST_SRC" ]; then check_plist "$PLIST_SRC" || exit 3; cp "$PLIST_SRC" "$PLIST"; echo "· plist 복사: $PLIST"; fi
  [ -f "$PLIST" ] || { echo "! plist가 없어요: $PLIST"; echo "  \"$0\" $BACKEND --plist \"\$HOME/Downloads/GoogleService-Info.plist\""; exit 3; }
  check_plist "$PLIST" || exit 3
fi

# 3) Local.xcconfig 바꾸기
set_key MC_USE_MOCK "$MOCK"
set_key MC_BACKEND "$BACKEND"
if [ "$BACKEND" != team ] || [ -n "$URL$BUNDLE_ARG$PROJECT_ARG" ]; then
  [ -n "$URL" ]         && set_key "MC_API_BASE_URL_$BACKEND" "$(xc_url "$URL")"
  [ -n "$BUNDLE_ARG" ]  && set_key "MC_BUNDLE_ID_$BACKEND" "$BUNDLE_ARG"
  [ -n "$PROJECT_ARG" ] && set_key "MC_FIREBASE_PROJECT_$BACKEND" "$PROJECT_ARG"
  [ "$BACKEND" = team ] || set_key "MC_FIREBASE_PLIST_$BACKEND" "$PLIST_NAME"
fi
if grep -qE '^[[:space:]]*MC_API_BASE_URL[[:space:]]*=' "$LOCAL"; then   # 예전 방식의 직접 주소는 전환을 막으므로 지운다
  tmp="$(mktemp)"; grep -vE '^[[:space:]]*MC_API_BASE_URL[[:space:]]*=' "$LOCAL" > "$tmp" && mv "$tmp" "$LOCAL"
  echo "· 예전 MC_API_BASE_URL 줄을 지웠어요"
fi

# 4) Xcode 프로젝트 다시 만들기 + 결과 확인
PROJ="$IOS_DIR/MemoryCapsule.xcodeproj"
if [ "$OPEN" = 1 ] && pgrep -x Xcode >/dev/null 2>&1; then   # 열려 있는 이 프로젝트 창은 닫았다가 다시 연다
  osascript -e "tell application \"Xcode\" to close (every workspace document whose path is \"$PROJ\") saving yes" >/dev/null 2>&1 || true
fi
cd "$IOS_DIR"
xcodegen generate >/dev/null
echo "· Xcode 프로젝트를 다시 만들었어요"
xcodebuild -project "$IOS_DIR/MemoryCapsule.xcodeproj" -scheme MemoryCapsule -showBuildSettings 2>/dev/null \
  | grep -E "^[[:space:]]*(MC_BACKEND|MC_USE_MOCK|MC_API_BASE_URL|PRODUCT_BUNDLE_IDENTIFIER) =" | sed 's/^ */  /'
echo "✓ $TARGET 로 바꿨어요."
if [ "$OPEN" = 1 ]; then
  open "$PROJ"
  echo "· Xcode에서 MemoryCapsule 프로젝트를 열었어요. ⇧⌘K(Clean Build Folder) 후 ⌘R로 실행하세요."
else
  echo "· Xcode에서 ⇧⌘K(Clean Build Folder) 후 실행하세요: open \"$PROJ\""
fi
