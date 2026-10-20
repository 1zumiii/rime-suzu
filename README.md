<h1 align="center">雾凇拼音 · 1zumiii Edition</h1>

<p align="center">
  基于 <a href="https://github.com/iDvel/rime-ice">雾凇拼音（rime-ice）</a> 的个人定制版本，增加本地小模型 AI 重排、最近使用优先、个人词对、语法模型和模糊音，并提供鼠须管（macOS）、小狼毫（Windows）和同文输入法 Trime（Android）的配置。<br>
  上游原版的说明见 <a href="https://github.com/iDvel/rime-ice">iDvel/rime-ice</a>。
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

- **AI 重排：** 本地小模型 [Suzu](https://github.com/1zumiii/Suzu) 按上文给候选打分，调整顺序。四字及以上的输入另有第二阶段。
- **候选生成：** 简拼和混合输入时，模型在词典里按上文挑出 Rime 没给的词，补进候选窗。默认开启。
- **统一排序：** 总分 = Rime 名次先验 + 上文权重 × 模型分 + 个人习惯，关闭 AI 时上文权重为 0。
- **个人词对与最近使用优先：** 同样的搭配再次出现时优先，最近上屏过的词提到第 2 位。记录只在本机。
- **语法模型、模糊音与误触容错：** 配置了万象语法模型，开启平翘舌与前后鼻音模糊音，相邻按键误触只处理 4 个字母及以上的音节。
- **Android 手机端：** 改版 Trime，推理在常驻进程 `rimellmd` 里，GBoard 风格布局，工具栏有 AI 状态徽标和模块状态页。

## 平台

| 平台 | 前端 | 使用情况 |
|---|---|---|
| macOS | 鼠须管 1.1.2（librime 1.16） | 主要的使用和测试平台 |
| Windows | 小狼毫 0.17 | AI 重排已在 Windows 11 上部署使用，其余功能验证较少 |
| Android | 改版同文输入法（Trime） | 在一台 ASUS Zenfone 10 上日常使用 |

AI 重排的推理核心、守护进程和 Trime 补丁在 [suzu-ime](https://github.com/1zumiii/suzu-ime) 仓库，本仓库只放配置和同步过来的 Lua 脚本。没有模型文件时不重排，输入不受影响。

## 快速开始

```bash
git clone https://github.com/1zumiii/rime-ice-Custom.git
cd rime-ice-Custom
./install.sh        # macOS：先自检，再备份到 ~/Library/Rime.backup-时间，然后安装
```

1. 从 Hugging Face 下载模型 [Suzu-2.4](https://huggingface.co/IzumiThe3rd/Suzu-2.4) 的 `suzu.gguf` 与 `suzu.vocab.txt`，放入用户目录（macOS 为 `~/Library/Rime`）。
2. 按 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md) 编译并安装推理核心 `rime_llm.so`。
3. 重启输入法。Windows 与 Android 的步骤见 [安装](docs/install.md)。Android 须注意：推理在常驻守护进程里，守护进程须借助 adb 或 Shizuku 启动，手机重启后要重新启动一次，配置前先准备好 adb 或 Shizuku。

默认开启 AI 重排，`Control+Shift+5` 在当前输入框临时开关。

## 文档

| 文档 | 内容 |
|---|---|
| [AI 重排](docs/ai-rerank.md) | 模型与性能、使用方法、上文与隐私、候选生成与统一排序、置信度门控 |
| [Android](docs/android.md) | 改版 Trime、守护进程、配置更新、模块状态页、手机端设置 |
| [其他功能](docs/features.md) | 个人词对、最近使用优先、本机记录一览、选词统计、语法模型、模糊音、小改动 |
| [安装](docs/install.md) | macOS、Windows、Android 的完整安装步骤 |
| [维护说明](docs/maintenance.md) | 补丁与部署的注意事项、同步上游、自定义内容的位置 |
| [误触容错](docs/typo-tolerance.md) | 相邻按键误触的数据与取舍 |

## 项目说明

本仓库基于 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 的 `da1fbe6`（2026-10-05），仅供个人使用，未做成通用发行版。默认分支为 `custom`，只从上游合并更新，不向上游推送；`main` 与上游保持一致。个人改动都放在独立文件里（`*.custom.yaml` 补丁和独立的 Lua 脚本），不直接修改上游的方案、词库和 Lua，合并上游更新时基本不会冲突。

## 致谢与许可

感谢 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 及其贡献者；[zhanghaozhecn/rime-llm-rerank](https://github.com/zhanghaozhecn/rime-llm-rerank)（AI 重排的原项目，署名许可，个人使用无限制）；[amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG)（万象语法模型）；[llama.cpp](https://github.com/ggml-org/llama.cpp)；[osfans/trime](https://github.com/osfans/trime)（同文输入法，GPL-3.0）及同文风主题作者暖暖；[Shizuku](https://github.com/RikkaApps/Shizuku)；以及 Rime、librime-lua、librime-octagram 的作者。

本仓库沿用上游的 GPL-3.0 许可证，见 [LICENSE](LICENSE)。模型文件和语法模型各自遵循发布方的许可。
