# 安装

## 一行命令安装

本节适用于 macOS 和 Windows。安装包包含编译好的推理核心、Suzu-UER12-PG100 模型、配置、雾凇词库和补充词条，无需 Git、Python 或自行编译。脚本先下载并核对 SHA-256，再备份现有配置，然后安装、部署。开发用的输入日志（选词统计、语料记录、输入事件流）默认关闭。最近用过的词、词对等个人习惯以明文保存在本机，见 [其他功能](features.md)。

```bash
# macOS（Apple 芯片，macOS 13 及以上，需先装好鼠须管）
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash
```

```powershell
# Windows（小狼毫 0.17）
irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
```

脚本会先列出操作并请求确认。Android 端可从 [suzu-ime 发布页](https://github.com/1zumiii/suzu-ime/releases/latest) 下载 APK，也可按下文从源码构建。Windows 可在解压后运行 `powershell -File install.ps1 -DryRun` 预览安装操作。

可选环境变量：`SUZU_BUNDLE_FILE` 使用本地的安装包 zip（跳过下载），`SUZU_TAG` 指定发布标签（默认取最新的正式版，旧的预览版为 `preview`）。安装时会询问是否下载约 400 MB 的万象语法模型，不安装也可使用。macOS 可在命令后加 `--with-gram` 直接下载，或加 `--no-gram` 跳过下载与询问（写成 `| bash -s -- macos --with-gram`）。Windows 对应 `-Grammar download` 与 `-Grammar skip`。

要换用 Suzu-UER6-PG200，macOS 将安装命令末尾改为 `| bash -s -- macos --model PG200`，Windows 在运行前设置环境变量 `$env:SUZU_MODEL = 'PG200'`。脚本从 Hugging Face 下载模型，校验 SHA-256，并按模型列表设置首位门控。下载或校验失败时，用户目录保持原样。桌面和 Android 共用 suzu-ime 仓库中的 `models.json`。

安装包由 `tools/make_bundle.py` 构建，包里带的 `README.txt` 有各平台的详细步骤、还原与卸载方法。

下面是不用安装包、从源码安装的步骤。

## 从源码安装：macOS（鼠须管）

```bash
git clone https://github.com/1zumiii/rime-suzu.git
cd rime-suzu
tools/install-dev.sh            # 先自检，再备份到 ~/Library/Rime.backup-时间，然后安装配置与词库包（保留词频库等个人数据）
tools/install-dev.sh --pack frost   # 换用其他词库包，省略时用 packs/DEFAULT 里写的
```

词库不在仓库里，`tools/install-dev.sh` 会调用 `tools/dict_pack.py` 按固定提交下载并安装词库包，首次需要联网并要求已安装 git 与 Python 3，之后用本地缓存（`~/.cache/suzu-dict-packs`）。`tools/install-dev.sh` 不覆盖以下文件：`*.userdb`（词频库）、`installation.yaml`、`user.yaml`、`recent_words.tsv`、`recent_pairs.tsv`、冷词记录和已存在的 `custom_phrase.txt`。安装后须重启输入法（`Squirrel --quit`，下次输入时由系统重新启动）。

AI 重排的推理核心 `rime_llm.so` 须自行编译，再用 suzu-ime 仓库的 `macos/install_llm.sh` 连同模型一起安装，步骤见 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md)。

## 从源码安装：Windows（小狼毫）

`windows/` 提供一套适配：

- `install.ps1`：先备份再安装，保留现有的 `default.custom.yaml` 和用户数据，安装后调用 `tools\dict_pack.py` 安装词库包（`-Pack 名字` 指定，须有 Python 3 与 git，首次需要联网）。
- `check_deployed.ps1`：部署后检查官方拼写规则是否被补丁覆盖。
- `rime_ice.custom.yaml`：已挂载 AI 重排（`ai_rerank_processor`、`ai_rerank_app_ctx`、`ai_rerank_filter`），移除了可能与它冲突的功能。
- `lua/ai_rerank_app_ctx.lua`：与 macOS、Android 共用，读应用里光标前的文字作上文（Windows 经 UIA 与 COM），随 `lua/` 一起拷进用户目录。

首次使用可先加 `-DryRun`，预览将要复制的文件，不执行修改。

**安装后须重新部署。** 最稳妥的办法是点击托盘图标中的“重新部署”。从自己的命令行直接运行 `WeaselDeployer.exe /deploy` 通常不会编译，反而会弹出“方案选单设定”窗口并一直挂着，因为它从当前进程里无法与服务端正常通信。要无人值守，须在小狼毫服务运行时通过交互式计划任务启动部署器，suzu-ime 的 `windows/deploy_airerank.ps1` 就是这样做的。脚本不复制 `weasel.yaml`，用户自己的小狼毫样式会保留，样式覆盖应写在 `weasel.custom.yaml` 中。

Windows 上的 AI 重排与 macOS、Android 共用同一套 `ai_rerank_*` Lua 脚本，光标上文接入层 `ai_rerank_app_ctx.lua` 也是共用的。推理核心 `rime_llm.dll` 由 suzu-ime 构建，构建、部署与回滚脚本见 [suzu-ime 的 Windows 说明](https://github.com/1zumiii/suzu-ime/blob/main/windows/README.md)。模型 `suzu.gguf` 与 `suzu.vocab.txt` 须放入用户目录。suzu-ime 的 `deploy_airerank.ps1` 用于把旧的 `llm_*` 配置切换到共用 Lua，用本仓库的模板新装的不需要它。

## 从源码安装：Android（Trime）

AI 重排的推理在独立的常驻守护进程 `rimellmd` 中运行，须借助 adb 或 Shizuku 启动。可在电脑端通过 adb 执行 `rimellmctl.sh start`，也可在手机上点按工具栏红色 AI 徽标，经 Shizuku 启动。手机重启后须重新启动守护进程。未启动时 AI 重排不生效，输入不受影响。

先通过 adb 连接手机。方案、Lua 和默认词库包已打包进 APK，无须单独推送配置。若需直接在手机上启动 AI 服务，另须安装并启动 Shizuku。

```bash
# 在 suzu-ime 仓库：android/trime/build_apk.sh        # 从源码编译改版 APK 并签名（首次需要 JDK 17、NDK r27d 等，见脚本开头）
adb install -r --user 0 <生成的 apk>
llm-android/deploy_trime.sh                          # 推送语法模型并触发部署，须先让 Trime 键盘弹出
# 在 suzu-ime 仓库：android/daemon/rimellmctl.sh start  # 在电脑端启动守护进程（也可在手机上点按红色 AI 徽标，经 Shizuku 启动）
```

安装后按引导启用并选择输入法，再按需下载 Suzu 模型、下载或导入语法模型，并启动 AI 服务。这些可选步骤可跳过，之后可在“设置 → 词库”中管理模型。上面的语法模型推送命令是电脑端的可选安装方式。

手动安装模型时，将从 Hugging Face 下载的 `suzu.gguf` 和 `suzu.vocab.txt` 放入 Trime 用户目录 `/sdcard/Android/data/com.osfans.trime/files/rime/`。完整说明、测试和基准脚本见 [suzu-ime 的 Android 说明](https://github.com/1zumiii/suzu-ime/blob/main/android/README.md)。
