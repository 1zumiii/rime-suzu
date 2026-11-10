#!/bin/bash
# 检查 lua/ 下由 suzu-ime 同步来的文件，与 lua/SUZU_IME_VERSION 记录的那个提交逐字节一致。
# 这些文件以 suzu-ime 为唯一来源（见 tools/sync_core.sh）；在本仓库直接改过、或同步后没更新版本记录，都会在这里失败。
# 用法：tools/check_core_sync.sh [suzu-ime 仓库路径]   （默认 ../suzu-ime，或环境变量 SUZU_IME；须是含该提交的完整克隆）
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${SUZU_IME:-$HERE/../suzu-ime}}"
read -r name rev < "$HERE/lua/SUZU_IME_VERSION"
[[ "$name" == "suzu-ime" && "$rev" =~ ^[0-9a-f]{7,40}$ ]] || { echo "lua/SUZU_IME_VERSION 的内容不是“suzu-ime <提交>”"; exit 1; }
git -C "$SRC" cat-file -e "$rev^{commit}" 2>/dev/null || { echo "$SRC 里没有提交 $rev"; exit 1; }
# 文件清单取自 sync_core.sh，两处不会各写一份
FILES="$(sed -n 's/^FILES="\(.*\)"$/\1/p' "$HERE/tools/sync_core.sh")"
[[ -n "$FILES" ]] || { echo "没能从 tools/sync_core.sh 读到文件清单"; exit 1; }
bad=0
for f in $FILES; do
  if ! git -C "$SRC" show "$rev:rime/lua/$f" | cmp -s - "$HERE/lua/$f"; then
    echo "不一致：lua/$f（与 suzu-ime $rev 的 rime/lua/$f 不同）"
    bad=1
  fi
done
[[ $bad -eq 0 ]] && echo "一致：$(echo $FILES | wc -w | tr -d ' ') 个文件与 suzu-ime $rev 相同" || { echo "用 tools/sync_core.sh 重新同步，不要直接改这些文件"; exit 1; }
