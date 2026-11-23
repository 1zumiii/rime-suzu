#!/bin/bash
# Suzu 一键安装（macOS，Apple 芯片，鼠须管 Squirrel）
# 用法：双击本文件；若提示“无法验证开发者”，右键选“打开”，或在终端里运行 bash install.command
# 选项：--with-gram 下载万象语法模型（约 400 MB，可选，不加时会询问）；--no-gram 不下载也不询问；--yes 不再询问，直接安装（不下载语法模型）
#       --model <编号> 换用模型名录里的其他模型（如 --model PG100），从 Hugging Face 下载并核对 sha256；不加时用安装包自带的模型
#       --list-models 列出名录里的模型后退出
# 环境变量：RIME_DIR 指定鼠须管用户目录（默认 ~/Library/Rime）；SUZU_MODEL 同 --model
#          SUZU_CATALOG_URL、SUZU_CATALOG_FILE 指定模型名录（默认 suzu-ime 仓库的 models.json，与 Android 共用）
# 会做的事：备份现有配置 → 安装配置、词库、Suzu 模型和推理核心 → 重新部署。
# 不会做的事：不创建任何统计或记录开关（选词统计、语料、输入事件流都保持关闭），不联网上传任何东西。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$HERE/payload"
DEST="${RIME_DIR:-$HOME/Library/Rime}"
SQ_APP="/Library/Input Methods/Squirrel.app"
SQ_BIN="$SQ_APP/Contents/MacOS/Squirrel"
TESTING="${SUZU_TEST:-}"        # 测试时跳过对鼠须管的检查、退出与重新部署
GRAMMAR=ask                      # 万象语法模型：ask 询问 / download 下载 / skip 不下载
YES="${SUZU_ASSUME_YES:-}"
MODEL="${SUZU_MODEL:-}"           # 模型名录里的编号；空表示用安装包自带的模型
LIST_MODELS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-gram) GRAMMAR=download ;; --no-gram) GRAMMAR=skip ;; --yes) YES=1 ;;
    --model) [[ $# -ge 2 ]] || { echo "--model 后面要写模型编号，例如 --model PG100"; exit 2; }; MODEL="$2"; shift ;;
    --model=*) MODEL="${1#--model=}" ;;
    --list-models) LIST_MODELS=1 ;;
    *) echo "未知选项 $1"; exit 2 ;;
  esac
  shift
done
# 模型名录：三端共用 suzu-ime 仓库根目录的 models.json，第一项是 Android 的默认模型。
# 条目只能指向 huggingface.co/IzumiThe3rd/ 下固定 revision 的文件并带 sha256，规则与 Android 的 SuzuModels.parse 相同。
CATALOG_URL="${SUZU_CATALOG_URL:-https://raw.githubusercontent.com/1zumiii/suzu-ime/main/models.json}"
# 万象语法模型：改善整句输入的同音字选择，鼠须管自带 octagram 插件。文件太大不放进安装包，安装时按用户选择从作者的发布页下载。
# 来源 amzxyz/rime-wanxiang-data（CC BY 4.0）。作者会更新这个文件，所以不写死哈希：下载前从发布信息里取作者公布的 sha256，下载后核对，对不上就不用。
GRAM_NAME=wanxiang-lts-zh-hans.gram
GRAM_URL=https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram
GRAM_API=https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS

# 从发布信息（JSON）里取语法模型的 sha256，用系统自带的 plutil 解析；取不到时返回非 0
gram_sha256() {
  local json="$1" n i name digest
  n="$(plutil -extract assets raw -o - "$json" 2>/dev/null)" || return 1
  for ((i = 0; i < n; i++)); do
    name="$(plutil -extract "assets.$i.name" raw -o - "$json" 2>/dev/null)" || continue
    [[ "$name" == "$GRAM_NAME" ]] || continue
    digest="$(plutil -extract "assets.$i.digest" raw -o - "$json" 2>/dev/null)" || return 1
    digest="${digest#sha256:}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    echo "$digest"
    return 0
  done
  return 1
}
# 取名录到 $1：本地文件优先（SUZU_CATALOG_FILE），否则下载
fetch_catalog() {
  if [[ -n "${SUZU_CATALOG_FILE:-}" ]]; then cp "$SUZU_CATALOG_FILE" "$1"
  else curl -fsSL --retry 2 -o "$1" "$CATALOG_URL"; fi
  [[ "$(plutil -extract schema raw -o - "$1" 2>/dev/null)" == 1 ]]
}
# 读名录第 $2 项的字段到 M_* 变量，不合格返回非 0
catalog_entry() {
  local j="$1" i="$2" k v
  for k in id title repo revision file sha256 size vocab_sha256 vocab_size top_gate; do
    v="$(plutil -extract "models.$i.$k" raw -o - "$j" 2>/dev/null)" || return 1
    printf -v "M_$k" '%s' "$v"
  done
  [[ "$M_id" =~ ^[A-Za-z0-9._-]{1,40}$ && -n "$M_title" && ${#M_title} -le 60 && "$M_repo" =~ ^IzumiThe3rd/[A-Za-z0-9._-]{1,96}$ && "$M_repo" != *..* \
    && "$M_revision" =~ ^[0-9a-f]{40}$ && "$M_file" =~ ^[A-Za-z0-9._-]{1,128}\.gguf$ && "$M_sha256" =~ ^[0-9a-f]{64}$ && "$M_vocab_sha256" =~ ^[0-9a-f]{64}$ \
    && "$M_size" =~ ^[0-9]{1,10}$ && "$M_vocab_size" =~ ^[0-9]{1,10}$ && "$M_top_gate" =~ ^[0-9]{1,2}(\.[0-9]{1,3})?$ ]]
}
catalog_count() { plutil -extract models raw -o - "$1" 2>/dev/null || echo 0; }
# 下载 $1 到 $2，核对体积 $3 与 sha256 $4
fetch_verified() {
  rm -f "$2"
  curl -L --fail --retry 2 --progress-bar -o "$2" "$1" || return 1
  [[ "$(stat -f %z "$2")" == "$3" && "$(shasum -a 256 "$2" | awk '{print $1}')" == "$4" ]]
}
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf '\n\033[31m出错：%s\033[0m\n' "$*" >&2; read -r -p "按回车关闭" _ || true; exit 1; }
# 没有语法模型时去掉配置里的 grammar 块与依赖它的 contextual_suggestions，免得每次部署都报错（与 Windows 安装脚本相同的规则）
remove_grammar_config() {
  [[ -f "$1" ]] || return 0
  perl -0pi -e 's/^[ \t]*#[^\n]*wanxiang[^\n]*\r?\n//mg; s/^([ \t]*)grammar:[ \t]*\r?\n(?:\1[ \t]+[^\n]*\r?\n)*//mg; s/^[ \t]*translator\/contextual_suggestions:[^\n]*\r?\n//mg' "$1"
}

say "Suzu 一键安装（macOS）"
if [[ -n "$LIST_MODELS" ]]; then
  CAT="$(mktemp -t suzu-models)"
  fetch_catalog "$CAT" || { rm -f "$CAT"; echo "取不到模型名录：$CATALOG_URL"; exit 1; }
  note "可用的模型（第一项是 Android 的默认模型，用 --model <编号> 选择）："
  n="$(catalog_count "$CAT")"
  for ((i = 0; i < n; i++)); do catalog_entry "$CAT" "$i" && note "  $M_id	$M_title	约 $(( (M_size + 500000) / 1000000 )) MB"; done
  rm -f "$CAT"; exit 0
fi
[[ -d "$PAYLOAD" && -f "$HERE/core/rime_llm.so" ]] || die "安装包不完整：找不到 payload 或 core/rime_llm.so。请重新解压。"
[[ "$(uname -m)" == "arm64" ]] || die "这个安装包只支持 Apple 芯片（M1 及以后）的 Mac，当前是 $(uname -m)。"
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$MAJOR" -ge 13 ]] || die "需要 macOS 13 或更新，当前是 $(sw_vers -productVersion)。"

if [[ -z "$TESTING" ]]; then
  if [[ ! -d "$SQ_APP" ]]; then
    say "还没有安装鼠须管（Squirrel）"
    if command -v brew >/dev/null 2>&1; then
      read -r -p "用 Homebrew 现在安装吗？(y/n) " yn
      if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
        brew install --cask squirrel || die "Homebrew 安装失败，请手动安装：https://github.com/rime/squirrel/releases"
      else
        die "请先安装鼠须管：https://github.com/rime/squirrel/releases ，装好后再运行本脚本。"
      fi
    else
      die "请先安装鼠须管：https://github.com/rime/squirrel/releases ，装好后再运行本脚本。"
    fi
  fi
  SQ_VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SQ_APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SQ_APP/Contents/Info.plist" 2>/dev/null || echo "?")"
  note "鼠须管版本 ${SQ_VER}（测试过 1.1.2）"
fi

# 选了模型就先取名录并下载、核对，全部通过后才开始改动用户目录
MODEL_SRC="$PAYLOAD"; MODEL_GATE=""; MODEL_TITLE=""
if [[ -n "$MODEL" ]]; then
  say "准备模型 $MODEL"
  MTMP="$(mktemp -d -t suzu-model)"; trap 'rm -rf "$MTMP"' EXIT
  fetch_catalog "$MTMP/models.json" || die "取不到模型名录：$CATALOG_URL"
  n="$(catalog_count "$MTMP/models.json")"; found=""
  for ((i = 0; i < n; i++)); do
    catalog_entry "$MTMP/models.json" "$i" || continue
    [[ "$(tr '[:upper:]' '[:lower:]' <<<"$M_id")" == "$(tr '[:upper:]' '[:lower:]' <<<"$MODEL")" ]] && { found=1; break; }
  done
  [[ -n "$found" ]] || die "模型名录里没有 $MODEL。可以用 --list-models 查看可用的编号。"
  MODEL_GATE="$M_top_gate"; MODEL_TITLE="$M_title"
  if [[ "$(shasum -a 256 "$PAYLOAD/suzu.gguf" | awk '{print $1}')" == "$M_sha256" ]]; then
    note "$M_title 就是安装包自带的模型，不用下载"
  else
    url="https://huggingface.co/$M_repo/resolve/$M_revision/$M_file"
    note "从 Hugging Face 下载 $M_title（约 $(( (M_size + 500000) / 1000000 )) MB）"
    fetch_verified "$url" "$MTMP/suzu.gguf" "$M_size" "$M_sha256" || die "模型下载失败或与名录里的 sha256 不一致，没有改动任何东西。网络受限时可以设置 HTTPS_PROXY 后重试。"
    fetch_verified "$url.vocab.txt" "$MTMP/suzu.vocab.txt" "$M_vocab_size" "$M_vocab_sha256" || die "词表下载失败或与名录里的 sha256 不一致，没有改动任何东西。"
    MODEL_SRC="$MTMP"
    note "已下载并校验（sha256 ${M_sha256:0:12}…）"
  fi
fi

say "将要做的事"
note "1. 把 $DEST 备份到 $DEST.backup-时间"
note "2. 退出鼠须管，安装配置、词库和 Suzu 模型到 ${DEST}（不覆盖你的词频库和已有的 default.custom.yaml）"
note "   rime_ice.custom.yaml 会换成本项目的版本，你在里面改过的设置可以从备份里找回"
note "3. 安装推理核心，重新部署"
[[ -n "$MODEL_TITLE" ]] && note "模型：${MODEL_TITLE}，首位门槛 ${MODEL_GATE}"
note "不会创建任何统计或记录开关，不上传任何内容。"
HAVE_GRAM=""; [[ -f "$DEST/$GRAM_NAME" ]] && HAVE_GRAM=1
if [[ -n "$HAVE_GRAM" ]]; then note "语法模型：用户目录里已有 ${GRAM_NAME}，直接使用"
else note "语法模型（可选，约 400 MB）：改善整句输入的同音字选择；不下载也能正常使用，只是整句质量差一点"; fi
INTERACTIVE=""; [[ -z "$YES" && -z "$TESTING" ]] && INTERACTIVE=1
if [[ -n "$INTERACTIVE" ]]; then
  read -r -p "确认安装吗？(y/n) " yn
  [[ "$yn" == "y" || "$yn" == "Y" ]] || { echo "已取消，没有改动任何东西。"; exit 0; }
fi
# 语法模型的选择在这里定下来；不询问的方式运行时默认不下载
if [[ -n "$HAVE_GRAM" ]]; then GRAMMAR=skip
elif [[ "$GRAMMAR" == ask ]]; then
  GRAMMAR=skip
  if [[ -n "$INTERACTIVE" ]]; then
    read -r -p "要下载万象语法模型吗？约 400 MB，来自 github.com/amzxyz/rime-wanxiang-data（y/n） " g
    [[ "$g" == "y" || "$g" == "Y" ]] && GRAMMAR=download
  fi
fi

mkdir -p "$DEST"

say "1/5 备份现有配置"
BACKUP="$DEST.backup-$(date +%Y%m%d-%H%M%S)"
rsync -a --exclude='*.gram' --exclude='build/' "$DEST"/ "$BACKUP"/
note "已备份到 ${BACKUP}（想还原时把它改回 $DEST 的名字即可）"

if [[ -z "$TESTING" ]]; then
  say "2/5 退出输入法"
  "$SQ_BIN" --quit 2>/dev/null || true
  sleep 1
else
  say "2/5 （测试模式，跳过）"
fi

say "3/5 安装配置和词库"
# 不覆盖：用户的词频库、同步目录、安装信息、自己的短语和已有的 default.custom.yaml（下面单独处理）
rsync -a \
  --exclude='installation.yaml' --exclude='user.yaml' --exclude='sync/' --exclude='*.userdb/' \
  --exclude='custom_phrase.txt' --exclude='default.custom.yaml' \
  "$PAYLOAD"/ "$DEST"/
[[ -e "$DEST/custom_phrase.txt" ]] || cp "$PAYLOAD/custom_phrase.txt" "$DEST/"
# default.custom.yaml 决定启用哪些输入方案。已有的并且已经包含 rime_ice 就保留，否则换成本项目的（旧的在备份里）
if [[ -e "$DEST/default.custom.yaml" ]] && grep -q "schema: rime_ice" "$DEST/default.custom.yaml"; then
  note "保留你现有的 default.custom.yaml（已包含 rime_ice）"
else
  cp "$PAYLOAD/default.custom.yaml" "$DEST/default.custom.yaml"
fi
note "配置与词库已就位"

say "4/5 安装 Suzu 模型和推理核心"
mkdir -p "$DEST/lua"
# 重要：已存在的 .so 不能原地覆盖（macOS 会缓存旧的代码签名，覆盖后输入法一加载就被系统杀掉），所以先删后拷并重新签名
rm -f "$DEST/lua/rime_llm.so"
cp "$HERE/core/rime_llm.so" "$DEST/lua/rime_llm.so"
xattr -dr com.apple.quarantine "$DEST/lua/rime_llm.so" 2>/dev/null || true
codesign --force --sign - "$DEST/lua/rime_llm.so" 2>/dev/null
codesign -v "$DEST/lua/rime_llm.so" || die "推理核心签名失败"
for f in suzu.gguf suzu.vocab.txt; do
  rm -f "$DEST/$f"
  cp "$MODEL_SRC/$f" "$DEST/$f"
done
# 换了模型时，按名录把首位门槛写进 rime_ice.custom.yaml（各模型的分数尺度不同）
if [[ -n "$MODEL_GATE" ]]; then
  perl -pi -e 's/^([ \t]*top_gate:[ \t]*)[0-9.]+/${1}'"$MODEL_GATE"'/' "$DEST/rime_ice.custom.yaml"
  grep -Eq "^[[:space:]]*top_gate:[[:space:]]*$MODEL_GATE([^0-9.]|\$)" "$DEST/rime_ice.custom.yaml" || die "没能把首位门槛写进 rime_ice.custom.yaml"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
note "模型、词表和推理核心已安装"

# 语法模型：已有就用；选了下载就下到临时文件、核对 sha256 后再放进用户目录；否则去掉配置里的 grammar
GRAM="$DEST/$GRAM_NAME"
GRAM_OK=""; [[ -f "$GRAM" ]] && GRAM_OK=1
if [[ -z "$GRAM_OK" && "$GRAMMAR" == download ]]; then
  say "下载万象语法模型（约 400 MB，视网速需要几分钟）"
  rm -f "$GRAM.part" "$GRAM.release.json"
  GRAM_SHA256=""
  if curl -fsSL --retry 2 -H "Accept: application/vnd.github+json" -o "$GRAM.release.json" "$GRAM_API"; then
    GRAM_SHA256="$(gram_sha256 "$GRAM.release.json" || true)"
  fi
  if [[ -z "$GRAM_SHA256" ]]; then
    note "取不到作者公布的校验值（网络问题或发布信息有变），先不下载语法模型。"
  elif ! curl -L --fail --retry 2 --progress-bar -o "$GRAM.part" "$GRAM_URL"; then
    note "语法模型下载失败（网络问题）。"
  elif [[ "$(shasum -a 256 "$GRAM.part" | awk '{print $1}')" != "$GRAM_SHA256" ]]; then
    note "语法模型与作者公布的校验值不一致，先不用它。"
  else
    mv "$GRAM.part" "$GRAM"; GRAM_OK=1; note "语法模型已下载并校验（sha256 ${GRAM_SHA256:0:12}…）"
  fi
  rm -f "$GRAM.part" "$GRAM.release.json"
fi
if [[ -n "$GRAM_OK" ]]; then [[ "$GRAMMAR" == download ]] || note "使用已有的语法模型"
else remove_grammar_config "$DEST/rime_ice.custom.yaml"; note "未安装语法模型：已从配置里去掉 grammar（不影响使用）"; fi

if [[ -z "$TESTING" ]]; then
  say "5/5 重新部署（首次编译词库，约 1 到 2 分钟，请耐心等待）"
  "$SQ_BIN" --reload || note "自动部署失败，请点菜单栏的输入法图标 → 重新部署"
else
  say "5/5 （测试模式，跳过）"
fi

say "安装完成"
cat <<MSG
  1. 打开 系统设置 → 键盘 → 输入法 →“编辑…”→ 左下角“+” → 中文 → 鼠须管（Squirrel），添加后用 Control+空格 切换。
     刚装好鼠须管时可能需要注销再登录一次，它才会出现在列表里。
  2. 打字试试：输入 zm 或 jingli。候选后面带 ◇ 表示 Suzu 参与了排序。
  3. 临时开关 AI：Control+Shift+5。输入内容全部在本机处理，不会上传。
  4. 选词统计、语料记录这类开发用的功能全部关闭，不会记录你的输入。
  5. 想退回原样：把 $BACKUP 改回 $DEST 的名字，或删除 $DEST/lua/rime_llm.so 只关闭 AI。
MSG
[[ -n "$GRAM_OK" ]] || note "6. 以后想加语法模型：重新运行安装并在询问时选 y（或加 --with-gram），也可以手动下载 $GRAM_NAME 放进 $DEST 后重新运行安装。"
[[ -z "$TESTING" ]] && read -r -p "按回车关闭" _ || true
