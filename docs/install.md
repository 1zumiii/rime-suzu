# 安装

## macOS（鼠须管）

```bash
git clone https://github.com/1zumiii/rime-ice-Custom.git
cd rime-ice-Custom
./install.sh            # 先自检，再备份到 ~/Library/Rime.backup-时间，然后安装（保留词频库等个人数据）
```

`install.sh` 不覆盖以下文件：`*.userdb`（词频库）、`installation.yaml`、`user.yaml`、`recent_words.tsv`、`recent_pairs.tsv`、冷词记录和已存在的 `custom_phrase.txt`。安装后须重启输入法（`Squirrel --quit`，下次输入时由系统重新启动）。

AI 重排的推理核心 `rime_llm.so` 须自行编译，再用 suzu-ime 仓库的 `macos/install_llm.sh` 连同模型一起安装，步骤见 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md)。

## Windows（小狼毫）

`windows/` 提供一套适配：

- `install.ps1`：先备份再安装，保留现有的 `default.custom.yaml` 和用户数据。
- `check_deployed.ps1`：部署后检查官方拼写规则是否被补丁覆盖。
- `rime_ice.custom.yaml`：移除了可能与 AI 重排冲突的功能。

这些脚本已在 Windows 上运行，并修复了几个问题：`robocopy` 遇到被占用的文件会无限等待，预览不显示文件列表，会覆盖用户自己的 `weasel.yaml` 样式。覆盖面仍然有限，首次使用先用 `-DryRun` 预览。

**安装后须点击托盘图标中的“重新部署”。** 命令行的 `WeaselDeployer.exe /deploy` 不会实际编译方案。脚本不复制 `weasel.yaml`，用户自己的小狼毫样式会保留；样式覆盖应写在 `weasel.custom.yaml` 中。

Windows 上的 AI 重排使用 suzu-ime 构建的 `rime_llm.dll`，Lua 脚本是上游 rime-llm-rerank 的 `llm_filter.lua`、`llm_processor.lua` 加 suzu-ime 中的[补丁](https://github.com/1zumiii/suzu-ime/blob/main/windows/rime-llm-rerank-windows.patch)，与 macOS 和 Android 的 Lua 不是同一套。构建、部署与回滚脚本见 [suzu-ime 的 Windows 说明](https://github.com/1zumiii/suzu-ime/blob/main/windows/README.md)。

## Android（Trime）

前提：已安装改版 Trime 并完成首次引导（选择“使用应用专属存储空间”），手机经 adb 连接，且已安装 Shizuku。

```bash
# 在 suzu-ime 仓库：android/trime/build_apk.sh        # 从源码编译改版 APK 并签名（首次需要 JDK 17、NDK r27d 等，见脚本开头）
adb install -r <生成的 apk>
llm-android/deploy_trime.sh --with-gram              # 推送配置和语法模型；须先让 Trime 键盘弹出，部署才会生效
# 在 suzu-ime 仓库：android/daemon/rimellmctl.sh start  # 在电脑端启动守护进程（也可在手机上点按红色 AI 徽标，经 Shizuku 启动）
```

Suzu 的 `suzu.gguf` 和 `suzu.vocab.txt`（从 Hugging Face 下载）须放入 Trime 的用户目录 `/sdcard/Android/data/com.osfans.trime/files/rime/`。完整说明、测试和基准脚本见 [suzu-ime 的 Android 说明](https://github.com/1zumiii/suzu-ime/blob/main/android/README.md)。
