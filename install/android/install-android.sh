#!/bin/bash
# Suzu 一键安装（Android，改版同文输入法 Trime），在 macOS 或 Linux 电脑上运行，手机用 USB 连接。
# 前提：手机上打开“开发者选项”里的“USB 调试”，连上电脑后在手机上点“允许此电脑调试”。
# 用法：bash install-android.sh [--dry-run] [--with-gram|--no-gram]    --dry-run 只检查手机并把文件推到一个临时目录，不安装、不部署、不启动；
#       --with-gram 下载万象语法模型（约 400 MB，不加时会询问），--no-gram 不下载也不询问
# 环境变量：ADB 指定 adb 路径（没有 adb 时脚本会下载谷歌官方的 platform-tools）；SUZU_ASSUME_YES=1 不再询问（测试用）
# 会做的事：安装改版 Trime → 推送配置、词库 → 启动 AI 推理进程（rimellmd）。
# 不会做的事：不创建任何统计或记录开关，不联网上传任何东西。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$HERE/payload"
PKG=com.osfans.trime
RIME=/sdcard/Android/data/$PKG/files/rime
YES="${SUZU_ASSUME_YES:-}"
DRY=0
GRAMMAR=ask                      # 万象语法模型：ask 询问 / download 下载 / skip 不下载
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --with-gram) GRAMMAR=download ;; --no-gram) GRAMMAR=skip ;; *) echo "未知选项 $a"; exit 2 ;; esac; done
# 万象语法模型：改善整句输入的同音字选择，改版同文自带 octagram 插件。文件太大不放进安装包，安装时按用户选择从作者的发布页下载到电脑，
# 核对作者公布的 sha256 后推到手机。来源 amzxyz/rime-wanxiang-data（CC BY 4.0）；作者更新文件后要同步更新这里的哈希。
GRAM_NAME=wanxiang-lts-zh-hans.gram
GRAM_URL=https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram
GRAM_SHA256=9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89
[[ "$DRY" == 1 ]] && RIME="${SUZU_RIME_DIR:-/sdcard/Download/suzu-dryrun-rime}"   # 试运行：推到临时目录，不动同文的真实用户目录

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf '\n\033[31m出错：%s\033[0m\n' "$*" >&2; exit 1; }
pause() { [[ -n "$YES" ]] && return 0; read -r -p "  $1（做完按回车）" _ || true; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
# 没有语法模型时去掉配置里的 grammar 块与依赖它的 contextual_suggestions，免得每次部署都报错（与 Windows 安装脚本相同的规则）
remove_grammar_config() {
  [[ -f "$1" ]] || return 0
  perl -0pi -e 's/^[ \t]*#[^\n]*wanxiang[^\n]*\r?\n//mg; s/^([ \t]*)grammar:[ \t]*\r?\n(?:\1[ \t]+[^\n]*\r?\n)*//mg; s/^[ \t]*translator\/contextual_suggestions:[^\n]*\r?\n//mg' "$1"
}
confirm() { [[ -n "$YES" ]] && return 0; read -r -p "  $1 (y/n) " yn; [[ "$yn" == "y" || "$yn" == "Y" ]]; }

[[ -f "$HERE/android/trime.apk" && -f "$HERE/android/rimellmd" && -d "$PAYLOAD" ]] || die "安装包不完整，请重新解压。"

say "Suzu 一键安装（Android）"

# ---- adb ----
ADB="${ADB:-}"
if [[ -z "$ADB" ]]; then
  if command -v adb >/dev/null 2>&1; then ADB="$(command -v adb)"
  elif [[ -x "$HERE/.platform-tools/platform-tools/adb" ]]; then ADB="$HERE/.platform-tools/platform-tools/adb"
  else
    case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) die "不支持的系统 $(uname -s)，Windows 请用 install-android.ps1" ;; esac
    say "没有找到 adb，下载谷歌官方的 platform-tools（约 12 MB）"
    mkdir -p "$HERE/.platform-tools"
    curl -L --fail --progress-bar -o "$HERE/.platform-tools/pt.zip" "https://dl.google.com/android/repository/platform-tools-latest-$OS.zip" || die "下载失败，请手动安装 adb 后重试"
    (cd "$HERE/.platform-tools" && unzip -q -o pt.zip && rm -f pt.zip)
    ADB="$HERE/.platform-tools/platform-tools/adb"
  fi
fi
"$ADB" start-server >/dev/null 2>&1 || true
export ADB

# ---- 设备 ----
say "1/6 检查手机"
state="$("$ADB" get-state 2>/dev/null || true)"
if [[ "$state" != "device" ]]; then
  "$ADB" devices | sed -n '2,$p' | sed '/^$/d' | sed 's/^/  /'
  die "没有可用的手机。请确认：已用 USB 连接；已打开 USB 调试；手机上点了“允许 USB 调试”（可勾选“始终允许”）。多台设备同时连接时请只留一台。"
fi
sh_() { "$ADB" shell "$@" | tr -d '\r'; }
ABI="$(sh_ getprop ro.product.cpu.abi)"
SDK="$(sh_ getprop ro.build.version.sdk)"
note "设备：$(sh_ getprop ro.product.model)，Android $(sh_ getprop ro.build.version.release)（API ${SDK}），$ABI"
[[ "$ABI" == "arm64-v8a" ]] || die "只支持 arm64 手机（当前 ${ABI}）。"
[[ "$SDK" -ge 30 ]] || die "需要 Android 11（API 30）或更新。"

# ---- 安装 APK ----
say "2/6 安装改版同文输入法"
if [[ "$DRY" == 1 ]]; then note "（试运行，跳过安装）"; else
if sh_ "pm list packages --user 0 $PKG" | grep -q "$PKG"; then note "手机上已有同文输入法，尝试直接覆盖安装（保留数据）"; fi
if ! out="$("$ADB" install -r --user 0 "$HERE/android/trime.apk" 2>&1)"; then
  if echo "$out" | grep -q -E "INCOMPATIBLE|signatures do not match|UPDATE_INCOMPATIBLE"; then
    note "手机上的同文输入法签名与本安装包不同（比如是应用商店的原版），必须先卸载才能装。"
    note "卸载会清空它的配置和词库（用户词库不会同步回来）。"
    confirm "确认卸载原版同文输入法并继续吗？" || die "已取消"
    "$ADB" shell pm uninstall --user 0 $PKG >/dev/null
    "$ADB" install -r --user 0 "$HERE/android/trime.apk" >/dev/null || die "安装失败"
  else
    echo "$out" | sed 's/^/  /'; die "APK 安装失败"
  fi
fi
note "已安装"
fi

# ---- 首次引导 ----
say "3/6 首次启动同文输入法"
if [[ "$DRY" == 1 ]]; then "$ADB" shell "mkdir -p $RIME"; fi
if ! sh_ "test -d $RIME && echo yes" | grep -q yes; then
  cat <<MSG
  请在手机上：
    1) 设置 → 系统 → 键盘 → 屏幕键盘 → 管理 → 打开“同文输入法”（不同品牌的位置略有差异）；
    2) 打开同文输入法的应用图标，按引导走完：启用输入法、切换为当前输入法，
       在“存储”一步选择“使用应用专属存储空间”。
MSG
  pause "完成上面的引导"
  for _ in $(seq 1 60); do sh_ "test -d $RIME && echo yes" | grep -q yes && break; sleep 2; done
  sh_ "test -d $RIME && echo yes" | grep -q yes || die "没有找到同文的用户目录 ${RIME}。请确认引导已走完且选了“使用应用专属存储空间”。"
fi
note "同文用户目录已就绪"

# ---- 推送配置 ----
say "4/6 推送配置和词库（约 80 MB）"
if [[ "$DRY" == 0 ]] && ! sh_ "test -d $RIME.bak-before-suzu && echo yes" | grep -q yes; then
  "$ADB" shell "cp -r $RIME $RIME.bak-before-suzu" && note "已备份原有配置到 $RIME.bak-before-suzu"
fi
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude='suzu.gguf' --exclude='suzu.vocab.txt' "$PAYLOAD"/ "$STAGE"/
# 手机上已有的 default.custom.yaml 如果已经包含 rime_ice 就保留（里面有你自己选的输入方案）
if sh_ "grep -q 'schema: rime_ice' $RIME/default.custom.yaml 2>/dev/null && echo yes" | grep -q yes; then
  rm -f "$STAGE/default.custom.yaml"; note "保留手机上现有的 default.custom.yaml"
fi
# 语法模型：手机上已有就用；选了下载就先下到电脑（安装包目录里，下次运行不用重下）、核对 sha256 再推到手机；否则去掉配置里的 grammar
GRAM_OK=""; LOCAL_GRAM="$HERE/$GRAM_NAME"
if sh_ "test -f $RIME/$GRAM_NAME && echo yes" | grep -q yes; then
  GRAM_OK=1; note "语法模型：手机上已有 $GRAM_NAME，直接使用"
else
  if [[ "$GRAMMAR" == ask ]]; then
    GRAMMAR=skip
    if [[ "$DRY" == 0 && -z "$YES" ]]; then
      note "语法模型（可选，约 400 MB）：改善整句输入的同音字选择；不下载也能正常使用，只是整句质量差一点"
      read -r -p "  要下载万象语法模型吗？来自 github.com/amzxyz/rime-wanxiang-data（y/n） " g
      [[ "$g" == "y" || "$g" == "Y" ]] && GRAMMAR=download
    fi
  fi
  if [[ "$GRAMMAR" == download && "$DRY" == 0 ]]; then
    if [[ -f "$LOCAL_GRAM" && "$(sha256_of "$LOCAL_GRAM")" == "$GRAM_SHA256" ]]; then note "使用安装包目录里已下载的语法模型"
    else
      note "正在下载语法模型（约 400 MB，视网速需要几分钟）"
      rm -f "$LOCAL_GRAM" "$LOCAL_GRAM.part"
      if ! curl -L --fail --retry 2 --progress-bar -o "$LOCAL_GRAM.part" "$GRAM_URL"; then note "语法模型下载失败（网络问题）。"
      elif [[ "$(sha256_of "$LOCAL_GRAM.part")" != "$GRAM_SHA256" ]]; then note "语法模型校验不一致（可能是作者更新了文件），先不用它。"
      else mv "$LOCAL_GRAM.part" "$LOCAL_GRAM"; note "语法模型已下载并校验"; fi
      rm -f "$LOCAL_GRAM.part"
    fi
    [[ -f "$LOCAL_GRAM" ]] && GRAM_OK=1
  fi
fi
if [[ -z "$GRAM_OK" ]]; then remove_grammar_config "$STAGE/rime_ice.custom.yaml"; note "未安装语法模型：已从配置里去掉 grammar（不影响使用）"; fi
"$ADB" push "$STAGE"/. "$RIME"/ | tail -1
if [[ -n "$GRAM_OK" && -f "$LOCAL_GRAM" ]] && ! sh_ "test -f $RIME/$GRAM_NAME && echo yes" | grep -q yes; then
  "$ADB" push "$LOCAL_GRAM" "$RIME/$GRAM_NAME.part" | tail -1 && "$ADB" shell "mv $RIME/$GRAM_NAME.part $RIME/$GRAM_NAME"
fi

if [[ "$DRY" == 1 ]]; then
  say "试运行结束"
  note "已把配置推到 ${RIME}（临时目录，可删除）。设备检查与文件推送正常。"
  "$ADB" shell "ls $RIME | head -30" | tr '\n' ' '; echo
  exit 0
fi

# ---- 部署 ----
say "5/6 让同文输入法编译词库"
cat <<MSG
  请在手机上点开任意输入框，让同文键盘弹出来，并保持手机亮屏（键盘没弹出时，部署指令会被忽略）。
MSG
pause "键盘已弹出"
"$ADB" shell "rm -f $RIME/build/rime_ice.table.bin" >/dev/null 2>&1 || true
"$ADB" shell "am broadcast -a $PKG.action.DEPLOY -p $PKG" >/dev/null
printf '  编译词库中（首次约 10 到 30 秒，手机慢的话更久）'
ok=""
for i in $(seq 1 90); do
  sleep 2; printf '.'
  if sh_ "test -f $RIME/build/rime_ice.table.bin && test -f $RIME/build/rime_ice.prism.bin && echo yes" | grep -q yes; then ok=1; break; fi
  [[ "$i" == 8 ]] && printf '\n  还没开始：请确认手机亮屏且键盘正在显示。'
done
echo
[[ -n "$ok" ]] || die "3 分钟内没有编译出词库。请保持键盘弹出后重新运行本脚本。"
note "词库已编译"

# ---- 推理进程 ----
say "6/6 启动 AI 推理进程"
chmod +x "$HERE/android/rimellmctl.sh"
export BIN="$HERE/android/rimellmd" MODEL="$PAYLOAD/suzu.gguf" VOCAB="$PAYLOAD/suzu.vocab.txt"
"$HERE/android/rimellmctl.sh" deploy     # 推送推理进程和模型（已有的会先停掉再换新）
"$HERE/android/rimellmctl.sh" start

say "安装完成"
cat <<MSG
  1. 在输入框里打 zm 或 jingli，候选后面带 ◇ 表示 Suzu 参与了排序。工具栏的“AI”徽标可以点一下开关。
  2. AI 推理进程在手机重启后会消失，AI 重排随之不生效（打字不受影响）。重启手机后，把手机连电脑，
     在本目录运行：bash restart-daemon.sh   （也可以装 Shizuku 后在手机上点工具栏的红色徽标启动）。
  3. 选词统计、语料记录这类开发用的功能全部关闭，不会记录你的输入，输入内容也不会上传。
  4. 想还原：卸载本输入法即可；原来的配置备份在手机的 $RIME.bak-before-suzu。
MSG
