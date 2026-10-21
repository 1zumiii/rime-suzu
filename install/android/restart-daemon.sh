#!/bin/bash
# 手机重启后，重新启动 AI 推理进程（把手机用 USB 连到电脑，已打开 USB 调试）。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-}"
if [[ -z "$ADB" ]]; then
  if command -v adb >/dev/null 2>&1; then ADB="$(command -v adb)"
  elif [[ -x "$HERE/.platform-tools/platform-tools/adb" ]]; then ADB="$HERE/.platform-tools/platform-tools/adb"
  else echo "没有找到 adb，请先运行 install-android.sh（它会下载 adb）"; exit 1; fi
fi
export ADB
chmod +x "$HERE/android/rimellmctl.sh"
export BIN="$HERE/android/rimellmd" MODEL="$HERE/payload/suzu.gguf" VOCAB="$HERE/payload/suzu.vocab.txt"
"$HERE/android/rimellmctl.sh" start
echo "已启动。在手机上打开键盘打几个字，AI 重排就会生效。"
