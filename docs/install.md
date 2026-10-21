# 安装

## 一行命令安装

最省事的办法。安装包（preview 预览版）里是编译好的推理核心、Suzu-2.4 模型、配置、雾凇词库和补充词条，不需要 git 或 Python，也不需要编译。脚本先下载并核对 sha256，再备份现有配置，然后安装、部署。选词统计、语料记录、输入事件流这类开发用的功能全部保持关闭，脚本不会创建它们的开关文件。

```bash
# macOS（Apple 芯片，macOS 13 及以上，需先装好鼠须管）
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash
# Android（电脑用 USB 连手机，电脑为 macOS 或 Linux）
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash -s -- android
```

```powershell
# Android（电脑为 Windows，PowerShell）
$env:SUZU_TARGET='android'; irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
```

```powershell
# Windows（小狼毫 0.17）
irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
```

脚本会先列出将要做的事并询问确认。macOS 的包完整验证过，Windows 与 Android 验证了各个步骤，完整流程还没有在干净设备上整体跑过。想先看看会做什么而不改动任何东西，Windows 可以把包解压后运行 `powershell -File install.ps1 -DryRun`。

可选环境变量：`SUZU_BUNDLE_FILE` 使用本地的安装包 zip（跳过下载），`SUZU_TAG` 指定发布标签（默认 `preview`）。macOS 可以在命令后加 `--with-gram`（写成 `| bash -s -- macos --with-gram`）另装约 380 MB 的万象语法模型，不装也能用。

安装包由 `tools/make_bundle.py` 构建，包里带的 `README.txt` 有各平台的详细步骤、还原与卸载方法。

下面是不用安装包、从源码安装的步骤。

## 从源码安装：macOS（鼠须管）

```bash
git clone https://github.com/1zumiii/rime-suzu.git
cd rime-suzu
tools/install-dev.sh            # 先自检，再备份到 ~/Library/Rime.backup-时间，然后安装配置与词库包（保留词频库等个人数据）
tools/install-dev.sh --pack frost   # 换用其他词库包；省略时用 packs/DEFAULT 里写的
```

词库不在仓库里，`tools/install-dev.sh` 会调用 `tools/dict_pack.py` 按固定提交下载并安装词库包，首次需要联网并要求已安装 git 与 Python 3，之后用本地缓存（`~/.cache/suzu-dict-packs`）。`tools/install-dev.sh` 不覆盖以下文件：`*.userdb`（词频库）、`installation.yaml`、`user.yaml`、`recent_words.tsv`、`recent_pairs.tsv`、冷词记录和已存在的 `custom_phrase.txt`。安装后须重启输入法（`Squirrel --quit`，下次输入时由系统重新启动）。

AI 重排的推理核心 `rime_llm.so` 须自行编译，再用 suzu-ime 仓库的 `macos/install_llm.sh` 连同模型一起安装，步骤见 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md)。

## 从源码安装：Windows（小狼毫）

`windows/` 提供一套适配：

- `install.ps1`：先备份再安装，保留现有的 `default.custom.yaml` 和用户数据；安装后调用 `tools\dict_pack.py` 安装词库包（`-Pack 名字` 指定，须有 Python 3 与 git，首次需要联网）。
- `check_deployed.ps1`：部署后检查官方拼写规则是否被补丁覆盖。
- `rime_ice.custom.yaml`：已挂载 AI 重排（`ai_rerank_processor`、`ai_rerank_win_ctx`、`ai_rerank_filter`），移除了可能与它冲突的功能。
- `lua/ai_rerank_win_ctx.lua`：Windows 专用，读应用里光标前的文字作上文，安装时拷进用户目录的 `lua/`。

`install.ps1` 的 `robocopy` 部分已在 Windows 上运行过，并修复了几个问题：`robocopy` 遇到被占用的文件会无限等待，预览不显示文件列表，会覆盖用户自己的 `weasel.yaml` 样式。覆盖面仍然有限，首次使用先用 `-DryRun` 预览。AI 重排的挂载模板、`ai_rerank_win_ctx.lua` 的拷贝与词库包安装是近期改动，尚未在 Windows 上实测。

**安装后须重新部署。** 最稳妥的办法是点击托盘图标中的“重新部署”。从自己的命令行直接运行 `WeaselDeployer.exe /deploy` 通常不会编译，反而会弹出“方案选单设定”窗口并一直挂着，因为它从当前进程里无法与服务端正常通信；要无人值守，须在小狼毫服务运行时通过交互式计划任务启动部署器，suzu-ime 的 `windows/deploy_airerank.ps1` 就是这样做的。脚本不复制 `weasel.yaml`，用户自己的小狼毫样式会保留；样式覆盖应写在 `weasel.custom.yaml` 中。

Windows 上的 AI 重排与 macOS、Android 共用同一套 `ai_rerank_*` Lua 脚本，另加 Windows 专用的 `ai_rerank_win_ctx.lua`。推理核心 `rime_llm.dll` 由 suzu-ime 构建；构建、部署与回滚脚本见 [suzu-ime 的 Windows 说明](https://github.com/1zumiii/suzu-ime/blob/main/windows/README.md)。模型 `suzu.gguf` 与 `suzu.vocab.txt` 须放入用户目录。suzu-ime 的 `deploy_airerank.ps1` 用于把旧的 `llm_*` 配置切换到共用 Lua，用本仓库的模板新装的不需要它。

## 从源码安装：Android（Trime）

先说明一点：AI 重排的推理不在 Trime 里，而在常驻守护进程 `rimellmd` 里。守护进程须借助 adb 或 Shizuku 启动，二者选一：电脑端用 adb 执行 `rimellmctl.sh start`，或在手机上点工具栏红色的 AI 徽标，经 Shizuku 启动。手机重启后守护进程会消失，须再启动一次；没有启动时 AI 重排不生效，输入不受影响。

前提：已安装改版 Trime 并完成首次引导（选择“使用应用专属存储空间”），手机经 adb 连接（部署配置与方式一启动守护进程用），并安装 Shizuku（方式二用）。

```bash
# 在 suzu-ime 仓库：android/trime/build_apk.sh        # 从源码编译改版 APK 并签名（首次需要 JDK 17、NDK r27d 等，见脚本开头）
adb install -r <生成的 apk>
llm-android/deploy_trime.sh --with-gram              # 推送配置、词库包和语法模型；须先让 Trime 键盘弹出，部署才会生效。PACK=frost 可换词库包
# 在 suzu-ime 仓库：android/daemon/rimellmctl.sh start  # 在电脑端启动守护进程（也可在手机上点按红色 AI 徽标，经 Shizuku 启动）
```

Suzu 的 `suzu.gguf` 和 `suzu.vocab.txt`（从 Hugging Face 下载）须放入 Trime 的用户目录 `/sdcard/Android/data/com.osfans.trime/files/rime/`。完整说明、测试和基准脚本见 [suzu-ime 的 Android 说明](https://github.com/1zumiii/suzu-ime/blob/main/android/README.md)。
