<h1 align="center">rime-suzu</h1>

<p align="center">
  集成本地 AI 小模型的 Rime 拼音配置：按上文重排候选、补充简拼候选，支持鼠须管（macOS）、小狼毫（Windows）和同文输入法 Trime（Android）。<br>
  方案基于 <a href="https://github.com/iDvel/rime-ice">雾凇拼音（rime-ice）</a>，词库以“词库包”的形式安装，可在雾凇、白霜等之间替换，其余标准 Rime 格式的词库理论上也兼容（只验证过雾凇和白霜）。
</p>

<p align="center">
  <img src="llm-android/docs/preview.png" alt="Android（同文输入法 Trime）预览：GBoard 风格主页面、AI 重排的候选" width="900"><br>
  <sub>Android（Trime）预览：GBoard 风格布局；工具栏的 <code>● AI</code> 为 AI 重排的状态和开关；候选后的 <code>◇</code> 表示模型参与了这次排序。</sub>
</p>

---

## 效果

测试方法：从留出集的句子里取一个词作为正确答案，在真实 librime 里逐键输入它的拼音或简拼，上文取答案之前的文字。表中的百分比是命中率：“首选”是正确答案排在第一位的题目占比，“前 5 名”是正确答案出现在前 5 个候选里的题目占比。题数为两字母简拼 407、混合输入 291、全拼 216，均为抽样。

| 输入 | 关 AI（Rime 原顺序） | Suzu-2.1 | Suzu-2.4 |
|---|---|---|---|
| 两字母简拼（如 `zm`），首选 | 10.7% | 41.8% | **49.4%** |
| 两字母简拼，前 5 名 | 32.8% | 73.7% | **77.9%** |
| 混合输入（如 `yangs`），首选 | 33.0% | 68.7% | **72.5%** |
| 全拼，首选 | 63.4% | **91.7%** | 90.7% |

全拼在 16000 题的维基评测上两个版本没有差别（+0.0，±0.3），表中全拼的 1 个点差别在 216 题的抽样误差内。留出集的答案偏冷门，真实输入多打常用词，实际收益以使用数据为准。推理在本机运行，模型文件约 44 MB，输入内容不出设备。三端的延迟与内存见 [AI 重排](docs/ai-rerank.md)。

## 功能

- AI 重排：本地小模型 [Suzu](https://github.com/1zumiii/Suzu) 按上文为候选打分，调整顺序。四字及以上的输入另有第二阶段。
- 候选生成：简拼和混合输入时，从词典中按上文筛选 Rime 未给出的词，补充到候选窗。默认开启。
- 统一排序：总分 = Rime 名次先验 + 上文权重 × 模型分 + 个人习惯，关闭 AI 时上文权重为 0。
- 个人词对与最近使用优先：同样的搭配再次出现时优先，最近上屏过的词提升到第 2 位。记录只保存在本机。
- 语法模型、模糊音与误触容错：配置万象语法模型，开启平翘舌与前后鼻音模糊音；相邻按键误触仅处理 4 个字母及以上的音节。
- Android 手机端：改版 Trime 采用 GBoard 风格布局，推理在常驻进程 `rimellmd` 中运行，工具栏提供 AI 状态徽标和模块状态页。

## 平台

| 平台 | 前端 | 使用情况 |
|---|---|---|
| macOS | 鼠须管 1.1.2（librime 1.16） | 主要的使用和测试平台 |
| Windows | 小狼毫 0.17 | AI 重排已在 Windows 11 上部署使用，其余功能验证较少 |
| Android | 改版同文输入法（Trime） | 在一台 ASUS Zenfone 10 上日常使用 |

AI 重排的推理核心、守护进程和 Trime 补丁位于 [suzu-ime](https://github.com/1zumiii/suzu-ime) 仓库，本仓库只保留配置和同步的 Lua 脚本。没有模型文件时不重排，输入不受影响。

已有 Rime 配置可通过 suzu-ime 的方案补丁接入 AI 重排，无需替换整套配置。调优后的参数已设为默认值，见 [接入已有的 Rime 配置](https://github.com/1zumiii/suzu-ime#接入已有的-rime-配置)。

## 快速开始

### 一行命令安装

安装包包含编译好的推理核心、模型、配置和词库，无需 git 或自行编译。脚本先下载并核对 sha256，再备份现有配置，然后安装并部署。

macOS（Apple 芯片，macOS 13 及以上，需先装好[鼠须管](https://github.com/rime/squirrel/releases)）：

```bash
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash
```

Android（电脑用 USB 连手机，手机须为 arm64、Android 11 及以上，电脑为 macOS 或 Linux；Windows 电脑见 [安装](docs/install.md)）：

```bash
curl -fsSL https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.sh | bash -s -- android
```

Windows（小狼毫 0.17，PowerShell；需要管理员权限时会弹出询问）：

```powershell
irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
```

脚本会先列出操作并请求确认，备份现有配置后再安装。当前发布的是 [preview 预览版](https://github.com/1zumiii/rime-suzu/releases/tag/preview)：macOS 安装包已完成完整验证；Windows 与 Android 已验证各个步骤，尚未在干净设备上验证完整流程。安装包关闭了选词统计、语料记录等开发功能，不会记录输入。

默认开启 AI 重排，`Control+Shift+5` 在当前输入框临时开关。Android 的推理在常驻守护进程里，手机重启后要重新启动一次，见 [安装](docs/install.md)。

### 从源码安装

开发者可从源码安装，并自行编译推理核心：

```bash
git clone https://github.com/1zumiii/rime-suzu.git
cd rime-suzu
tools/install-dev.sh                 # 安装配置和词库包（首次需要联网下载词库）
tools/install-dev.sh --pack frost    # 换用其他词库包，见下文
```

之后从 Hugging Face 下载模型 [Suzu-2.4](https://huggingface.co/IzumiThe3rd/Suzu-2.4) 的 `suzu.gguf` 与 `suzu.vocab.txt`，按 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md) 编译并安装推理核心 `rime_llm.so`，重启输入法。Windows 与 Android 的步骤见 [安装](docs/install.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [AI 重排](docs/ai-rerank.md) | 模型与性能、使用方法、上文与隐私、候选生成与统一排序、置信度门控 |
| [Android](docs/android.md) | 改版 Trime、守护进程、配置更新、模块状态页、手机端设置 |
| [其他功能](docs/features.md) | 个人词对、最近使用优先、本机记录一览、选词统计、语法模型、模糊音、小改动 |
| [安装](docs/install.md) | macOS、Windows、Android 的完整安装步骤 |
| [词库包](docs/dictionary-packs.md) | 词库不放在仓库里：安装与替换词库、新增词库包、本仓库的补充词条 |
| [维护说明](docs/maintenance.md) | 补丁与部署的注意事项、与雾凇上游的关系、自定义内容的位置 |
| [误触容错](docs/typo-tolerance.md) | 相邻按键误触的数据与取舍 |

## 项目说明

本仓库的方案文件与配置结构来自 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 的 `da1fbe6`（2026-10-05），此后独立维护，不再定期合并上游。上游重要的 Lua 或方案修复按需摘取。

仓库保留配置、Lua 脚本和各端部署脚本，不含词库。词库按 `packs/packs.tsv` 登记的固定提交安装，当前支持雾凇和白霜，新增或更换方法见 [词库包](docs/dictionary-packs.md)。个人改动放在独立文件中，包括 `*.custom.yaml` 补丁和 Lua 脚本；补充词条放在 `extras/extra.dict.yaml`，可叠加到任何词库包上。本项目仅供个人使用，尚非通用发行版。

## 致谢与许可

感谢 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 及其贡献者；[gaboolic/rime-frost](https://github.com/gaboolic/rime-frost)（白霜拼音词库，GPL-3.0，词库包之一）；[zhanghaozhecn/rime-llm-rerank](https://github.com/zhanghaozhecn/rime-llm-rerank)（AI 重排的原项目，署名许可，个人使用无限制）；[amzxyz/rime-wanxiang-data](https://github.com/amzxyz/rime-wanxiang-data)（万象语法模型，CC BY 4.0）；[llama.cpp](https://github.com/ggml-org/llama.cpp)；[osfans/trime](https://github.com/osfans/trime)（同文输入法，GPL-3.0）及同文风主题作者暖暖；[Shizuku](https://github.com/RikkaApps/Shizuku)；以及 Rime、librime-lua、librime-octagram 的作者。

本仓库沿用雾凇的 GPL-3.0 许可证，见 [LICENSE](LICENSE)。词库包、模型文件和语法模型各自遵循发布方的许可，来源与许可证登记在 `packs/packs.tsv`。
