#!/bin/bash
# 安装前自检：在临时目录编译，确认补丁没有把官方的拼写规则（尤其是简拼 abbrev）覆盖掉。
# 用法：tools/verify_build.sh   （通过返回 0）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="/Library/Input Methods/Squirrel.app/Contents/SharedSupport"
DEPLOYER="/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rsync -a --exclude='.git/' --exclude='others/' --exclude='build/' --exclude='*.userdb/' "$SRC"/ "$TMP"/
"$DEPLOYER" --build "$TMP" "$SHARED" "$TMP/build" >/dev/null 2>&1 || { echo "自检失败：编译出错"; exit 1; }

SCHEMA="$TMP/build/rime_ice.schema.yaml"
OFFICIAL=$(git -C "$SRC" show upstream/main:rime_ice.schema.yaml 2>/dev/null \
  | awk '/^  algebra:/{f=1;next} f&&/^  [a-z_]/{exit} f&&/^    - /' | wc -l | tr -d ' ')
BUILT=$(awk '/^  algebra:/{f=1;next} f&&/^  [a-z_]/{exit} f&&/^    - /' "$SCHEMA" | wc -l | tr -d ' ')
ABBREV=$(grep -c '"abbrev/' "$SCHEMA" || true)

# emoji_defer_filter 必须排在 simplifier@emoji 之后，否则它看不到 emoji 候选
EMOJI_LN=$(grep -n 'simplifier@emoji' "$SCHEMA" | head -1 | cut -d: -f1)
DEFER_LN=$(grep -n 'emoji_defer_filter' "$SCHEMA" | head -1 | cut -d: -f1)
if [[ -n "$DEFER_LN" && ( -z "$EMOJI_LN" || "$DEFER_LN" -lt "$EMOJI_LN" ) ]]; then
  echo "自检失败：emoji_defer_filter 排在 simplifier@emoji 之前（官方过滤器列表可能变了，请调整 rime_ice.custom.yaml 里的 @after 10）"
  exit 1
fi

# 方案开关：ai_rerank 与 ai_stage2 必须同时出现在编译后的方案里。
# （曾因 rime_ice.custom.yaml 里写了两行同名的 "switches/@next"，YAML 重复键只留一个，把 ai_rerank 开关挤掉了）
for SW in ai_rerank ai_stage2; do
  if ! grep -q "name: $SW\$" "$SCHEMA"; then
    echo "自检失败：编译后的方案里没有开关 $SW（rime_ice.custom.yaml 里的 switches 写法有问题？同一个键不能出现两次，要用 \"switches/+\" 一次追加）"
    exit 1
  fi
done

if [[ "$ABBREV" -lt 2 || "$BUILT" -lt "$OFFICIAL" ]]; then
  echo "自检失败：官方拼写规则被覆盖（官方 $OFFICIAL 条，编译后 $BUILT 条，abbrev $ABBREV 条）"
  exit 1
fi
echo "自检通过：拼写规则 $BUILT 条（官方 $OFFICIAL 条），abbrev $ABBREV 条"
