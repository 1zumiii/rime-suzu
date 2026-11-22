<h1 align="center">rime-suzu</h1>

<p align="center">
  集成本地 AI 小模型的 Rime 拼音配置：按上文重排候选、补充简拼候选，支持鼠须管（macOS）、小狼毫（Windows）和同文输入法 Trime（Android）。<br>
  方案基于 <a href="https://github.com/iDvel/rime-ice">雾凇拼音（rime-ice）</a>，词库以“词库包”的形式安装，支持雾凇和白霜，可随时切换。
</p>

<p align="center">
  <img src="llm-android/docs/preview.png" alt="Android（同文输入法 Trime）预览：GBoard 风格主页面、AI 重排的候选" width="900"><br>
  <sub>Android（Trime）预览：GBoard 风格布局。工具栏的 <code>● AI</code> 为 AI 重排的状态和开关，候选后的 <code>◇</code> 表示模型参与了这次排序。</sub>
</p>

---

## 效果

当前模型为 [Suzu-UER6-KD500](https://huggingface.co/IzumiThe3rd/Suzu-UER6-KD500)。下表在鼠须管自带的 librime 中逐键输入两字母简拼题，启用 Rime 候选、候选生成和统一排序，报按帖子划分的约 1,190 道验证题的首选准确率。题目取自知乎、天涯和清华树洞，答案为原文里的词。

| 设置 | 首选 |
|---|---:|
| 不用模型分（同一批候选按 Rime 原名次排序） | 28.6% |
| Suzu-2.4，首位门槛 2.5 | 39.3% |
| Suzu-UER6-KD500，首位门槛 1.5（默认） | **54.0%** |

KD500 在这批题里改动首位 547 次，其中 12 次把原本正确的首选改错。Suzu-2.4 一行来自较早一轮评测，验证题为 1,192 道。全拼同音词 1,293 题上，KD500 与 Suzu-2.4 持平（92.81% 对 92.73%）。

评测题只认原词，上文完整。日常输入里用户词典已学到大部分常用词，实际收益比表中小。

推理在本机运行，模型文件约 52.8 MB，输入内容不出设备。手机上（ASUS Zenfone 10，守护进程 2 线程，每组 10 个候选），同结构模型每次打分比 Suzu-2.4 多 1.5～2 ms。打分加候选生成的 P99 约 20 ms，连续输入时约 26 ms，常驻内存约 151 MB（Suzu-2.4 约 109 MB）。

## 功能

- AI 重排：本地小模型 [Suzu](https://github.com/1zumiii/Suzu) 按上文为候选打分，调整顺序。四字及以上的输入另有第二阶段。
- 候选生成：简拼和混合输入时，从词典中按上文筛选 Rime 未给出的词，补充到候选窗。默认开启。
- 统一排序：总分 = Rime 名次先验 + 上文权重 × 模型分 + 个人习惯，关闭 AI 时上文权重为 0。
- 个人词对与最近使用优先：同样的搭配再次出现时优先，最近上屏过的词提升到第 2 位。记录只保存在本机。
- 语法模型、模糊音与误触容错：配置万象语法模型，开启平翘舌与前后鼻音模糊音。相邻按键误触仅处理 4 个字母及以上的音节。
- Android 手机端：改版 Trime 采用 GBoard 风格布局，推理在常驻进程 `rimellmd` 中运行，工具栏提供 AI 状态徽标和功能状态页。

## 平台

| 平台 | 前端 | 使用情况 |
|---|---|---|
| macOS | 鼠须管 1.1.2（librime 1.16） | 主要的使用和测试平台 |
| Windows | 小狼毫 0.17 | AI 重排已在 Windows 11 上部署使用，其余功能验证较少 |
| Android | 改版同文输入法（Trime） | 在一台 ASUS Zenfone 10 上日常使用 |

AI 重排的推理核心、守护进程和改版 Trime 的源码位于 [suzu-ime](https://github.com/1zumiii/suzu-ime) 仓库，本仓库只保留配置和同步的 Lua 脚本。没有模型文件时不重排，输入不受影响。

已有 Rime 配置可通过 suzu-ime 的方案补丁接入 AI 重排，无需替换整套配置。调优后的参数已设为默认值，见 [接入已有的 Rime 配置](https://github.com/1zumiii/suzu-ime#接入已有的-rime-配置)。

## 快速开始

### 一行命令安装

macOS 与 Windows 的安装包包含编译好的推理核心、模型、配置和词库，无需 git 或自行编译。脚本先下载并核对 sha256，再备份现有配置，然后安装并部署。

macOS（Apple 芯片，macOS 13 及以上，需先装好[鼠须管](https://github.com/rime/squirrel/releases)）：

```bash
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash
```

Windows（小狼毫 0.17，PowerShell，需要管理员权限时会弹出询问）：

```powershell
irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
```

脚本会先列出操作并请求确认，备份现有配置后再安装。版本与下载文件见 [桌面端发布页](https://github.com/1zumiii/rime-suzu/releases/latest)。开发用的输入日志（选词统计、语料记录、输入事件流）在安装包里默认关闭。最近用过的词、词对等个人习惯以明文保存在本机用户目录，用于调整候选顺序，可随时删除，见 [其他功能](docs/features.md)。

桌面端默认开启 AI 重排，`Control+Shift+5` 在当前输入框临时切换。

Android 端从 [suzu-ime 发布页](https://github.com/1zumiii/suzu-ime/releases/latest) 下载 APK，支持 arm64、Android 11 及以上。方案、Lua 和默认词库随 APK 提供。安装后可在引导页下载模型，再通过 Shizuku 启动 AI 服务。手机重启后须重新启动服务，详见 [安装](docs/install.md)。

### 从源码安装

开发者可从源码安装，并自行编译推理核心：

```bash
git clone https://github.com/1zumiii/rime-suzu.git
cd rime-suzu
tools/install-dev.sh                 # 安装配置和词库包（首次需要联网下载词库）
tools/install-dev.sh --pack frost    # 换用其他词库包，见下文
```

下载 [Suzu-UER6-KD500](https://huggingface.co/IzumiThe3rd/Suzu-UER6-KD500) 的 GGUF 权重和配套词表，分别保存为 `suzu.gguf` 和 `suzu.vocab.txt`。按 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md) 编译并安装推理核心 `rime_llm.so`，再重启输入法。Windows 与 Android 的步骤见 [安装](docs/install.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [AI 重排](docs/ai-rerank.md) | 模型与性能、使用方法、上文与隐私、候选生成与统一排序、置信度门控 |
| [Android](docs/android.md) | 改版 Trime、AI 服务、配置更新、功能状态页、手机端设置 |
| [其他功能](docs/features.md) | 个人词对、最近使用优先、本机记录一览、选词统计、语法模型、模糊音、小改动 |
| [安装](docs/install.md) | macOS、Windows、Android 的完整安装步骤 |
| [词库包](docs/dictionary-packs.md) | 词库不放在仓库里：安装与替换词库、新增词库包、本仓库的补充词条 |
| [设置页](docs/settings.md) | macOS 与 Windows 的网页设置：排序参数、候选映射、词库包切换、一键重新部署 |
| [维护说明](docs/maintenance.md) | 补丁与部署的注意事项、与雾凇上游的关系、自定义内容的位置 |
| [误触容错](docs/typo-tolerance.md) | 相邻按键误触的数据与取舍 |

## 项目说明

本仓库的方案文件与配置结构来自 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 的 `da1fbe6`（2026-10-05），此后独立维护，不再定期合并上游。上游重要的 Lua 或方案修复按需摘取。

仓库保留配置、Lua 脚本和各端部署脚本，不含词库。词库按 `packs/packs.tsv` 登记的固定提交安装，当前支持雾凇和白霜，新增或更换方法见 [词库包](docs/dictionary-packs.md)。个人改动放在独立文件中，包括 `*.custom.yaml` 补丁和 Lua 脚本。补充词条放在 `extras/extra.dict.yaml`，可叠加到任何词库包上。

## 致谢与许可

感谢 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 及其贡献者、[gaboolic/rime-frost](https://github.com/gaboolic/rime-frost)（白霜拼音词库，GPL-3.0，词库包之一）、[zhanghaozhecn/rime-llm-rerank](https://github.com/zhanghaozhecn/rime-llm-rerank)（AI 重排的原项目，署名许可，个人使用无限制）、[amzxyz/rime-wanxiang-data](https://github.com/amzxyz/rime-wanxiang-data)（万象语法模型，CC BY 4.0）、[llama.cpp](https://github.com/ggml-org/llama.cpp)、[osfans/trime](https://github.com/osfans/trime)（同文输入法，GPL-3.0）及同文风主题作者暖暖、[Shizuku](https://github.com/RikkaApps/Shizuku)，以及 Rime、librime-lua、librime-octagram 的作者。

本仓库沿用雾凇的 GPL-3.0 许可证，见 [LICENSE](LICENSE)。词库包、模型文件和语法模型各自遵循发布方的许可，来源与许可证登记在 `packs/packs.tsv`。
