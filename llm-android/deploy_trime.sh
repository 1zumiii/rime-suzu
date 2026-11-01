#!/bin/bash
# 把语法模型推送到手机上的改版 Trime，并触发部署。方案、Lua 和默认词库包已打包进 APK，这里不推送配置。
# 前提：手机已用 adb 连接，Trime 已安装并弹出过键盘（输入法服务运行时才会响应部署广播）。
# 用法：llm-android/deploy_trime.sh [--dry-run]
#   --dry-run    只说明会做什么，不改动手机
# 环境变量：ANDROID_SERIAL 指定设备；GRAM 指定语法模型路径（默认 ~/Library/Rime/wanxiang-lts-zh-hans.gram，约 380 MB）。
set -euo pipefail

ADB="${ADB:-adb}"
PKG=com.osfans.trime
DEST=/sdcard/Android/data/$PKG/files/rime
GRAM="${GRAM:-$HOME/Library/Rime/wanxiang-lts-zh-hans.gram}"
DRY=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; *) echo "unknown option $a"; exit 2;; esac; done

"$ADB" get-state >/dev/null 2>&1 || { echo "没有连接的设备（adb devices）"; exit 1; }
"$ADB" shell "pm list packages $PKG" | grep -q "$PKG" || { echo "手机上没有安装 Trime"; exit 1; }
"$ADB" shell "test -d $DEST" || { echo "$DEST 不存在：请先打开 Trime 走完首次启动引导"; exit 1; }
[[ -f "$GRAM" ]] || { echo "找不到语法模型 $GRAM"; exit 1; }

WANT=$(stat -f%z "$GRAM" 2>/dev/null || stat -c%s "$GRAM")
HAVE=$("$ADB" shell "stat -c %s $DEST/$(basename "$GRAM") 2>/dev/null || echo 0" | tr -d '\r')
if [[ "$WANT" == "$HAVE" ]]; then
  echo "语法模型已在手机上（大小一致），跳过"
elif [[ $DRY -eq 1 ]]; then
  echo "将推送 $GRAM → $DEST"
else
  "$ADB" push "$GRAM" "$DEST"/ | tail -1
fi
[[ $DRY -eq 1 ]] && { echo "将触发部署"; exit 0; }

# 接收器只在输入法服务运行时才响应，也就是手机上要先弹出过键盘
if ! "$ADB" shell "pidof $PKG" | grep -q '[0-9]'; then
  echo ">>> 手机上 Trime 进程没有在运行：请在手机上打开任意输入框，把键盘弹出来，再重新运行本脚本"
  exit 1
fi
"$ADB" shell "am broadcast -a $PKG.action.DEPLOY -p $PKG" | tail -1
echo "已触发部署"
