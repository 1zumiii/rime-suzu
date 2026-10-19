#!/bin/bash
# 从 suzu-ime 仓库同步 AI 重排的 Lua 文件到本仓库的 lua/。这些文件以 suzu-ime 为唯一来源，勿在本仓库直接修改。
# 用法：tools/sync_core.sh [suzu-ime 仓库路径]   （默认 ../suzu-ime，或环境变量 SUZU_IME）
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${SUZU_IME:-$HERE/../suzu-ime}}"
[[ -d "$SRC/rime/lua" ]] || { echo "找不到 $SRC/rime/lua：请指定 suzu-ime 仓库路径"; exit 1; }
FILES="ai_rerank_filter.lua ai_rerank_processor.lua personal_pairs.lua corpus_archive.lua recent_boost_filter.lua rerank_json.lua input_log.lua rank_unified.lua"
for f in $FILES; do
  [[ -f "$SRC/rime/lua/$f" ]] || { echo "缺少 $SRC/rime/lua/$f"; exit 1; }
  cp "$SRC/rime/lua/$f" "$HERE/lua/$f"
done
printf 'suzu-ime %s\n' "$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)" > "$HERE/lua/SUZU_IME_VERSION"
echo "已同步：$FILES（$(cat "$HERE/lua/SUZU_IME_VERSION")）"
