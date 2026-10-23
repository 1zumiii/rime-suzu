#!/bin/bash
# Suzu 一行安装：下载安装包、校验、解压并运行里面的安装脚本。
#   macOS（Apple 芯片）：  curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash
#   Android（在 macOS 或 Linux 电脑上，手机用 USB 连接）：
#                          curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash -s -- android
#   其他选项原样传给里面的安装脚本，例如 macOS 另装语法模型：... | bash -s -- macos --with-gram
# Windows 请用 PowerShell，见 install.ps1。
# 环境变量：SUZU_BUNDLE_FILE 使用本地的安装包 zip（跳过下载）；SUZU_BASE_URL 指定安装包所在的地址；SUZU_TAG 指定发布标签（默认 preview）。
# 说明：安装包里是已编译好的推理核心、模型、配置和词库，下载后会先核对 sha256 再运行；脚本不会上传任何内容。
set -euo pipefail

REPO="1zumiii/rime-suzu"
TAG="${SUZU_TAG:-preview}"
BASE="${SUZU_BASE_URL:-https://github.com/$REPO/releases/download/$TAG}"
WORK="${SUZU_WORK_DIR:-$HOME/.cache/suzu-install}"

usage() {
  cat <<MSG
用法：
  macOS：   curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash
  Android： curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- android
MSG
}

target="${1:-}"
case "$(uname -s)" in
  Darwin) [[ -n "$target" ]] || target=macos ;;
  Linux)
    [[ -n "$target" ]] || { echo "Linux 上只支持给 Android 手机安装。"; usage; exit 1; } ;;
  *) echo "这个脚本只支持 macOS 和 Linux。Windows 请用 PowerShell，见 https://github.com/$REPO"; exit 1 ;;
esac
[[ $# -gt 0 ]] && shift
case "$target" in
  macos)   asset="suzu-macos-arm64.zip";   entry="install.command" ;;
  android) asset="suzu-android-arm64.zip"; entry="install-android.sh" ;;
  *) echo "不认识的目标：$target"; usage; exit 2 ;;
esac

mkdir -p "$WORK"
zip="$WORK/$asset"
if [[ -n "${SUZU_BUNDLE_FILE:-}" ]]; then
  zip="$SUZU_BUNDLE_FILE"
  [[ -f "$zip" ]] || { echo "找不到 $zip"; exit 1; }
else
  echo "下载 $asset ……"
  curl -fL --progress-bar -o "$zip.part" "$BASE/$asset" || { echo "下载失败：$BASE/$asset"; echo "安装包可能还没有发布，或网络不通。"; exit 1; }
  curl -fsSL -o "$zip.sha256" "$BASE/$asset.sha256" || { echo "没有找到校验文件 $BASE/$asset.sha256"; exit 1; }
  want="$(awk '{print $1}' "$zip.sha256")"
  got="$(shasum -a 256 "$zip.part" | awk '{print $1}')"
  [[ "$want" == "$got" ]] || { echo "校验失败：下载的文件与发布的 sha256 不一致，已停止。"; rm -f "$zip.part"; exit 1; }
  mv "$zip.part" "$zip"
  echo "校验通过（sha256 ${got:0:12}…）"
fi

dir="$WORK/bundle"
rm -rf "$dir"; mkdir -p "$dir"
unzip -q "$zip" -d "$dir"
inner="$(find "$dir" -maxdepth 1 -mindepth 1 -type d | head -1)"
[[ -f "$inner/$entry" ]] || { echo "安装包里没有 ${entry}，包不完整。"; exit 1; }
xattr -dr com.apple.quarantine "$inner" 2>/dev/null || true
cd "$inner"
# 通过管道运行时标准输入是脚本本身，安装脚本里的提问要从终端读
if ( : </dev/tty ) 2>/dev/null; then exec bash "./$entry" "$@" </dev/tty; else exec bash "./$entry" "$@"; fi   # 没有终端（如在自动化环境里）时用原来的标准输入
