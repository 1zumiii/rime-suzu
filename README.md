<h1 align="center">雾凇拼音 · 1zumiii Edition</h1>

<p align="center">
  基于 <a href="https://github.com/iDvel/rime-ice">雾凇拼音（rime-ice）</a> 的个人定制版本，增加本地小模型 AI 重排、最近使用优先、个人词对、语法模型和模糊音，并提供鼠须管（macOS）、小狼毫（Windows）和同文输入法 Trime（Android）的配置。<br>
  上游原版的说明见 <a href="https://github.com/iDvel/rime-ice">iDvel/rime-ice</a>。
</p>

<p align="center">
  <img src="llm-android/docs/preview.png" alt="Android（同文输入法 Trime）预览：GBoard 风格主页面、AI 重排的候选" width="900"><br>
  <sub>Android（Trime）预览：GBoard 风格布局；工具栏的 <code>● AI</code> 为 AI 重排的状态和开关；候选后的 <code>◇</code> 表示该首选经上文重排得出。</sub>
</p>

---

## 项目说明

本仓库基于 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 的 `da1fbe6`（2026-10-05），加入了日常使用中需要的若干功能，仅供个人使用，未做成通用发行版。

| 平台 | 前端 | 使用情况 |
|---|---|---|
| macOS | 鼠须管 1.1.2（librime 1.16） | 主要的使用和测试平台 |
| Windows | 小狼毫 0.17 | 有一套配置，AI 重排已在 Windows 11 上部署使用，其余功能验证较少 |
| Android | 改版同文输入法（Trime） | 在一台 ASUS Zenfone 10 上日常使用 |

- 默认分支为 `custom`，只从上游合并更新，不向上游推送，也不提交 PR。`main` 与上游保持一致，只用于同步。
- 个人改动都放在独立文件里（`*.custom.yaml` 补丁和独立的 Lua 脚本），不直接修改上游的方案、词库和 Lua，合并上游更新时基本不会冲突。
- AI 重排的推理核心、守护进程和 Trime 补丁在 [suzu-ime](https://github.com/1zumiii/suzu-ime) 仓库，本仓库只放配置和同步过来的 Lua 脚本。

## AI 重排

AI 重排依据本次输入会话中刚上屏的内容，对候选词重新排序。四字及以上的输入另有第二阶段重排。简拼和混合输入（如 `zm`、`yangs`）时，还会由模型在词典里按上文挑出 Rime 没有给出的词，补进候选窗（候选生成）。排序方式默认是统一排序：总分 = Rime 名次先验 + 上文相关的模型分 + 个人习惯。

### 模型与性能

模型是输入法专用的小模型 [Suzu](https://github.com/1zumiii/Suzu)，当前版本为 Suzu-2.1，权重发布在 [Hugging Face](https://huggingface.co/IzumiThe3rd/Suzu-2.1)（上一版 [Suzu-2](https://huggingface.co/IzumiThe3rd/Suzu-2) 仍可用）。Suzu 由 Qwen3.5 蒸馏而来，使用字符级词表，Q8_0 量化后约 44 MB。

在公开评测集上，Suzu-2 的混合口径准确率为 92.8%，与 Qwen3.5-0.8B 的 92.7% 持平；难例为 72.4%，高于后者的 70.7%。Suzu-2.1 在 Suzu-2 的权重上续训，补充了日常口语、技术和二次元语料，结构、词表和体积不变。在新留出的领域题上，混合准确率提升 12～14.5 个百分点，维基评测提升 0.5 个百分点。领域题为合成句子，每个题集约 200 题，区间约 ±5 个百分点，只能判断量级，详见 Suzu 仓库的 README。

推理核心为 2026-10-19 重写的版本，三端共用同一份代码。新旧核心在同一模型下逐题打分一致，下表是按键仿真的实测：

| 平台 | 打分中位数 | 打分 p99 | 每次按键最坏 | 常驻内存 |
|---|---|---|---|---|
| macOS（进程内，4 线程） | 3.8 ms | 9.1 ms | 11.9 ms | 71.8 MB |
| Windows（进程内，4 线程） | 2.7 ms | 4.7 ms | 9.1～9.7 ms | 69.5 MB（工作集） |
| Android（守护进程，2 线程） | 11.2 ms | 19.3 ms | 36.8 ms | 约 61 MB |

Android 的数字经 adb 端口转发测得，含转发开销。以上延迟不含候选生成。开启候选生成后，手机的守护进程常驻内存约 80 MB，Mac 的打分中位数约 4.5 ms；Windows 上的候选生成待测。旧核心的对应数字、测试方法和尚未验证的项目见 [suzu-ime 的 README](https://github.com/1zumiii/suzu-ime)。

### 使用

- 启用：把 `suzu.gguf` 和 `suzu.vocab.txt` 放入用户目录（macOS 为 `~/Library/Rime`，Android 为 Trime 的用户目录）即自动使用。没有这两个文件时不重排，输入不受影响。推理核心须另行安装，见下文“安装”。
- 标记：重排后的首选带 `◇`，四字两阶段得出的首选带 `◈`。
- 开关：AI 开关默认开启，按输入框独立生效（鼠须管的每个输入框为独立会话），`Control+Shift+5` 在当前输入框临时开关。需要默认关闭时，把 `rime_ice.custom.yaml` 里 `ai_rerank` 开关的 `reset` 改为 `0`。四字以上输入的第二阶段由另一个开关 `ai_stage2` 控制（“单段”或“两段”），默认“两段”。
- 触发范围：从 2 个字母起触发（`code_pattern: [a-z]{2,}`），含简拼；单个字母不重排，避开置顶词。只在前 80 个候选内重排，其余候选保持惰性生成，避免雾凇大词库造成卡顿。
- 内存：Suzu 默认常驻，不空闲卸载。

### 上文、隐私与时限

macOS 和 Android 的上文只取自 Rime 的 `commit_history`，即本次会话中经输入法上屏的内容，不读取任何应用内的文字。切换输入框后的第一个词因此不会重排。Windows 默认经 UIA 和 COM 读取光标前的文字，读不到时使用上屏历史；设置 `llm_rerank/context_source: history` 可改为与 macOS 相同的做法。

AI 重排本身不联网，也不写入任何包含输入内容的文件。最近使用和个人词对的记录见下文“本机记录一览”，均为本机文件。上游原有的训练语料、事件日志和词频落盘已删除。

每次打分都有时限，桌面端最多等 40 ms，手机上最多约 65 ms。上文还没预解码完时，核心在时限内现场解码；时限内没算完，当次按键保持原顺序，结果进缓存，下一次按键直接用上。输入串变短（退格修改）时不执行第二阶段。第一阶段结果按“上文 + 候选”缓存，输入同一个词的各个字母时不重复推理。

局限：评测集来自维基百科，偏书面语，不代表真实输入的准确率。候选生成只在词典词里挑，词典外的字串（新词、网络用语）不生成；Windows 上尚未部署，待测。

### 候选生成与统一排序

候选生成默认开启，只用于简拼和混合输入。核心把输入切成“完整音节或声母”的序列，在 `cn_dicts/base.dict.yaml` 与 `ext.dict.yaml` 的 2 到 3 字词里，按上文逐字搜索概率最高的几个词；全拼输入由核心判定不适用，行为不变。词在 Rime 候选里的沿用 Rime 的名次，不在的先验名次取词频名次，排在打分组之后。

留出集抽样的真实链路对照里，相对此前的配置（Mac 的两字母简拼不重排），两字母简拼首选由 10.7% 升到 35.1%，答案进前 5 名由 32.8% 升到 71.5%；混合输入首选由 62.9% 升到 68.4%。与“统一排序但不生成”相比，两字母简拼的答案进前 5 名由 47.4% 升到 71.5%。完整的对照表与局限见 suzu-ime 的 README。统一排序的名次先验系数目前取 0.25（默认 1.0 在干净上文的留出集上比旧排序低 3.7 个点），真实输入下是否合适待回放数据校准。旧的融合与门控保留为回退，把 `llm_rerank/ranker` 设为 `legacy` 即可。

### 置信度门控

置信度门控只用于旧排序（`ranker: legacy`），统一排序不使用。默认关闭（`llm_rerank/gate_margin: 0`）。开启后，模型选出的首位须比 Rime 原首位的融合分高出至少这个值才换位，否则保持 Rime 原顺序，减少“帮倒忙”。输入只有 1～2 个字母时用更高的门槛 `gate_margin_short`。有纠错记忆命中的候选不受门控限制。

手机端默认开启，两个门槛分别为 0.5 和 1.5，初值为估计值。选词统计会记录每次的 margin、是否被门控和模型首位的原位次，`tools/select_stats_report.py` 据此给出分桶校准表，用来调整门槛。

### Android

同一套配置和 AI 重排也用于手机端。推理运行在独立的常驻进程 `rimellmd` 中，Trime 内只有一个轻量客户端；输入法进程被终止或崩溃时，模型不受影响。设计、实测数据和文件清单见 [suzu-ime 的 Android 说明](https://github.com/1zumiii/suzu-ime/blob/main/android/README.md)。

- 改版 Trime：在上游固定提交上应用[一个补丁](https://github.com/1zumiii/suzu-ime/blob/main/android/trime/patches/0001-ai-rerank-daemon.patch)，新增 `INTERNET` 权限（只连接本机 127.0.0.1）、亮灭屏通知、工具栏 `● AI` 状态徽标，以及经 Shizuku 启动守护进程的入口。仓库不含 APK，须自行编译，并使用自己的密钥签名。
- 守护进程：由 adb 或 Shizuku 以 shell 身份启动。监督进程看护工作进程，工作进程被终止、崩溃或无响应时按退避时间自动重启，并记录原因。与 Trime 之间经 127.0.0.1 通信，使用随机令牌认证。所有 I/O 都有时限，连不上时当次不重排，输入不受影响。
- 手动启停：点按工具栏的 `● AI` 徽标开关 AI。绿色为在线，黄色为加载或重启中，灰色为已关闭，红色为离线（点按后经 Shizuku 启动）。长按可查看内存、延迟、重启次数和上次退出原因。关闭时立即卸载模型，进程只保持待命；开启时立即加载。新安装默认关闭，用户的选择会被保留。
- 孤儿保护：Trime 被卸载后，其数据目录随之消失。守护进程发现该目录连续 10 分钟不存在时自行退出，监督进程随之结束。重新安装 Trime 后，点按红色徽标即可再次启动。
- 配置更新：左侧三个点打开的面板里有“从仓库更新”，从指定的 GitHub 仓库下载最新配置并覆盖到输入法，推送后无需连接电脑。仓库地址和分支可修改，fork 本仓库后填入自己的地址即可。覆盖前自动备份上一个版本（只保留一份），更新后连续崩溃两次会自动回退，也可手动回退。词频、用户词、最近使用记录、语法模型和推理模型不受影响。
- 模型文件：`suzu.gguf` 和 `suzu.vocab.txt` 放入 Trime 用户目录后重启守护进程即启用。可选的 `suzu.name`（一行文字，如 `Suzu-2.1`）用于在长按徽标的详情里显示模型名。
- 模块状态：三个点的面板里有“模块状态”，只读，显示守护进程、排序方式、候选生成、各类记录的状态。
- 手机端设置：2 个推理线程、9 个候选、候选生成每层展开 10 个首字、第二阶段默认“两段”，可在三个点的开关面板里切到“单段”。这些设置只写在 `llm-android/trime/*.overlay.yaml` 中，部署时才追加，不影响 macOS 和 Windows。
- GBoard 风格布局：同文风主题改为 GBoard 的主页面和 `?123` 数字符号页，符号页每页 4 行 × 7 列，按键使用线条图标。空格键在中文模式下显示“拼音”，英文模式下显示“English”。补丁由 [gen_tongwenfeng_patch.py](llm-android/trime/gen_tongwenfeng_patch.py) 依据主题源文件生成。
- 适用范围：只在这一台手机上验证过，其他机型和 Trime 版本未测试。手机重启后须先启动 Shizuku，才能启动守护进程。

## 其他功能

### 个人词对与纠错记忆

个人词对记录“前一个词 → 当前词”的使用次数，同样的搭配再次出现时优先。计数带时间衰减（14 天衰减到约 1/e），也参与 AI 重排的融合打分（`llm_rerank/pair_gamma`，默认 1.5，设为 0 关闭）。

- 记录保存在用户目录的 `recent_pairs.tsv`，内容为相邻上屏词的明文（最多 6000 条，保留 90 天）。删除该文件并重新部署即可清空。
- 只记含中文的词，不记英文和数字串；超过 8 个字的整句不记。
- “前一个词”只在上一次上屏后 20 秒内有效；退格、方向键、回车之后失效。
- 纠错记忆：在“前一个词 + 输入的拼音”这个情境下记住所选的词，选了非首位的权重更大。同样的情境再出现时，选过的词优先（`llm_rerank/corr_gamma`，默认 3.0，0 关闭）。
- 开关为 `recent_boost_filter/pairs`（默认 true）。提升阈值为 `min_pair`（默认 1.5，约需同一搭配重复出现两次，避免单次误选被固化）。

### 最近使用优先

最近 72 小时内上屏过的词会提升到第 2 个候选位置（最多 2 个词），置顶词仍在最前。参数在 `rime_ice.custom.yaml` 的 `recent_boost_filter`（`window_hours`、`idx`、`max_boost` 等）。记录保存在用户目录的 `recent_words.tsv`，内容为上屏词的明文（默认最多 3000 条）。原有的词频学习（userdb）不变，本功能是在其基础上的补充。

### 本机记录一览

下列文件都在用户目录（macOS 为 `~/Library/Rime`，手机为 Trime 的 `files/rime`）。内容为明文，只在本机，不会同步，也不会进入仓库。删除对应文件即可清空。

| 文件 | 记录内容 | 何时记录 | 保留策略 |
|---|---|---|---|
| `recent_words.tsv` | 上屏的词：时间戳和词 | 每次上屏词组、用户词或整句（不记英文、数字、标点、emoji 和计算器结果） | 活动文件保留最近 3000 条，更早的移到 `recent_words.archive.tsv` |
| `recent_pairs.tsv` | 相邻两个上屏词：时间戳、前一个词、当前词 | 上一个词在 20 秒内，且两个词都含中文、不超过 8 个字 | 活动文件保留 90 天内、最多 6000 条，其余移到 `recent_pairs.archive.tsv` |
| `recent_choices.tsv` | 纠错记忆：时间戳、前一个词、输入的拼音、所选词、权重 | 每次选词（选了非首位的权重 2.0，选了首位的 0.5），前一个词在 20 秒内、输入为小写拼音、所选词含中文且不超过 8 个字 | 180 天内最多 4000 条，其余进归档 |
| `select_stats.tsv` | 纯数字的选词位次（见下文） | 只在存在 `select_stats.enabled` 时 | 超过 2 MB 改名为 `.old`，只保留一份 |
| `select_corpus.tsv` | 训练样本（明文）：上文最后 6 个字、所选词、最终与原顺序的首位、类型 | 只在存在 `select_corpus.enabled` 时；所选不是首位的全记，选了首位的随机抽 10% | 超过 2 MB 分卷并压缩，不丢弃 |
| `select_replay.jsonl` | 回放数据（明文）：拼音、上文最后 30 个字、所选词、打分组里各候选的模型分与各融合项计数 | 与 `select_corpus.tsv` 同一开关、同一批样本 | 超过 2 MB 分卷并压缩，不丢弃 |
| `input_log.jsonl` | 输入事件流（明文）：选词（拼音、所选词、候选与各项分数）、上屏文字、删除与失步事件 | 只在存在 `input_log.enabled` 时 | 超过 2 MB 分卷并压缩；分卷保留 30 天（`llm_rerank/input_log_days`），过期删除 |

归档文件超过 512 KB 时，改名为带时间的分卷，并尽量用 gzip 压缩（Windows 上没有 gzip，保留明文分卷）。归档写入成功后才从活动文件里删除旧记录，写入失败不会丢失记录。

本仓库不包含任何个人语料或个人权重，也不发布用个人数据训练的模型。个人化微调的方法见 [个人化说明](https://github.com/1zumiii/suzu-ime/blob/main/docs/personalization.md)，可在自己的设备上复现；微调出的权重只应留在本机。

### 选词统计

选词统计默认关闭，用来以真实输入评估重排是否有帮助。每次选词在 `select_stats.tsv` 里记一行纯数字：时间戳、AI 开关、模型、输入字母数、参与重排的候选数、所选候选在原顺序和最终顺序里的位次、上文长度档、候选字数、候选类型。不含任何输入的文字、拼音和候选文字。

- 开启：在用户目录新建空文件 `select_stats.enabled`，新开的输入会话生效。删除该文件即停止，删除 `select_stats.tsv` 即清空。
- 汇总：`python3 tools/select_stats_report.py select_stats.tsv`（脚本在 [suzu-ime](https://github.com/1zumiii/suzu-ime/blob/main/tools/select_stats_report.py)），给出原顺序第一位被选中的比例与重排后的比例、重排救回与帮倒忙的次数，并按模型、输入长度、上文长度分组。

### 语法模型

本仓库配置了万象语法模型 `wanxiang-lts-zh-hans.gram`（约 379 MB），用于改善整句输入时的同音字选择，鼠须管自带 octagram 插件。模型文件不在仓库中，须自行从 [amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG/releases) 下载，放入 `~/Library/Rime/`。缺少该文件时，相关配置会被忽略，不影响使用。整句候选带 `❖` 标记（`model_badge_filter.lua`）。

### 模糊音与误触容错

模糊音开启了平翘舌（z/zh、c/ch、s/sh）和前后鼻音（an/ang、en/eng、in/ing）。规则在 `algebra_extra.yaml`，由 `tools/gen_typo_rules.py` 生成。需要关闭某一组时，在脚本中注释对应行并重新生成。

相邻按键误触容错只处理 4 个字母及以上的音节，末字母只允许换成 i、u、v，避免把两个字吞成一个。邻键替换类错拼的首选命中率由 0.7% 提高到 32.9%，吞字比例约 0.3%～2.6%。数据与取舍见 `docs/typo-tolerance.md`。

### 其他小改动

| 改动 | 说明 |
| --- | --- |
| 冷词降频 | 启用上游自带的 `cold_word_drop`：`Control+j` 降频，`Control+x` 隐藏，`Control+d` 强制删词 |
| 英文、自定义短语调频 | `melt_eng` 打开用户词典，`custom_phrase` 改为 `tabledb`（Rime 会回写 `custom_phrase.txt`） |
| 中英混输自动空格 | 启用上游自带的 `cn_en_spacer`，`VIP中P` → `VIP 中 P` |
| 每页候选 5 个 | 7 个时短词容易折到第二行 |
| 方案列表 | 只保留 `rime_ice`（全拼）。九宫格和各种双拼方案文件已从本仓库删除，需要时从上游取回，并在 `default.custom.yaml` 的 `schema_list` 中添加 |
| 外观 | `squirrel.custom.yaml`：微信键盘配色、横排候选、OpenSans 字体 |

## 安装

### macOS（鼠须管）

```bash
git clone https://github.com/1zumiii/rime-ice-Custom.git
cd rime-ice-Custom
./install.sh            # 先自检，再备份到 ~/Library/Rime.backup-时间，然后安装（保留词频库等个人数据）
```

`install.sh` 不覆盖以下文件：`*.userdb`（词频库）、`installation.yaml`、`user.yaml`、`recent_words.tsv`、`recent_pairs.tsv`、冷词记录和已存在的 `custom_phrase.txt`。安装后须重启输入法（`Squirrel --quit`，下次输入时由系统重新启动）。

AI 重排的推理核心 `rime_llm.so` 须自行编译，再用 suzu-ime 仓库的 `macos/install_llm.sh` 连同模型一起安装，步骤见 [suzu-ime 的 macOS 说明](https://github.com/1zumiii/suzu-ime/blob/main/macos/README.md)。

### Windows（小狼毫）

`windows/` 提供一套适配：

- `install.ps1`：先备份再安装，保留现有的 `default.custom.yaml` 和用户数据。
- `check_deployed.ps1`：部署后检查官方拼写规则是否被补丁覆盖。
- `rime_ice.custom.yaml`：移除了可能与 AI 重排冲突的功能。

这些脚本已在 Windows 上运行，并修复了几个问题：`robocopy` 遇到被占用的文件会无限等待，预览不显示文件列表，会覆盖用户自己的 `weasel.yaml` 样式。覆盖面仍然有限，首次使用先用 `-DryRun` 预览。

**安装后须点击托盘图标中的“重新部署”。** 命令行的 `WeaselDeployer.exe /deploy` 不会实际编译方案。脚本不复制 `weasel.yaml`，用户自己的小狼毫样式会保留；样式覆盖应写在 `weasel.custom.yaml` 中。

Windows 上的 AI 重排使用 suzu-ime 构建的 `rime_llm.dll`，Lua 脚本是上游 rime-llm-rerank 的 `llm_filter.lua`、`llm_processor.lua` 加 suzu-ime 中的[补丁](https://github.com/1zumiii/suzu-ime/blob/main/windows/rime-llm-rerank-windows.patch)，与 macOS 和 Android 的 Lua 不是同一套。构建、部署与回滚脚本见 [suzu-ime 的 Windows 说明](https://github.com/1zumiii/suzu-ime/blob/main/windows/README.md)。

### Android（Trime）

前提：已安装改版 Trime 并完成首次引导（选择“使用应用专属存储空间”），手机经 adb 连接，且已安装 Shizuku。

```bash
# 在 suzu-ime 仓库：android/trime/build_apk.sh        # 从源码编译改版 APK 并签名（首次需要 JDK 17、NDK r27d 等，见脚本开头）
adb install -r <生成的 apk>
llm-android/deploy_trime.sh --with-gram              # 推送配置和语法模型；须先让 Trime 键盘弹出，部署才会生效
# 在 suzu-ime 仓库：android/daemon/rimellmctl.sh start  # 在电脑端启动守护进程（也可在手机上点按红色 AI 徽标，经 Shizuku 启动）
```

Suzu 的 `suzu.gguf` 和 `suzu.vocab.txt`（从 Hugging Face 下载）须放入 Trime 的用户目录 `/sdcard/Android/data/com.osfans.trime/files/rime/`。完整说明、测试和基准脚本见 [suzu-ime 的 Android 说明](https://github.com/1zumiii/suzu-ime/blob/main/android/README.md)。

## 注意事项

修改补丁和部署时须注意以下各项，均为实际遇到过的问题：

1. 不要用 `__patch` 引用带 `/+` 的文件。这样 `/+` 不会按“追加”处理，而会整段替换官方的 `speller/algebra`，导致所有简拼（`zm`、`zuijd`）失效。应使用 `"speller/algebra/+": { __include: algebra_extra:/rules }`。`tools/verify_build.sh` 会在安装前检查这一点。
2. 不要用 `@last`。它表示“替换最后一项”，会挤掉官方末尾的 `uniquifier`。追加应使用 `@before last` 或 `@after last`。
3. 补丁键按字典序依次生效，带数字的 `@before N` 依赖前面的插入。同一个键只能写一次，因此 `@before 0`、`@after last` 这类位置各只能由一个组件使用。
4. 替换已存在的 `rime_llm.so` 须先删除再复制。原地覆盖会使 macOS 缓存的旧代码签名与新内容不符，加载时内核直接以 `SIGKILL (Code Signature Invalid)` 终止进程，输入法一启动即崩溃，反复崩溃后系统会将其从已启用的输入法中移除。suzu-ime 的 `macos/install_llm.sh` 已按此处理。
5. 鼠须管的开关状态按输入框独立保存，新输入框会恢复默认值，因此需要常开的开关应把默认值设为开。
6. 不要把绑定了引擎的对象缓存为 Lua 模块级变量。鼠须管的每个输入框和应用都有独立的引擎，而 Lua 模块是共享的。把 `Component.Translator(...)` 存为模块级变量后，后创建的输入框会使用已销毁引擎中的翻译器，`query` 时访问野指针，进程因段错误退出（崩溃报告中为 `ScriptTranslator::Query`）。应存放在 `env` 中，随引擎一同销毁。
7. 上游的 `.gitignore` 会忽略 `*.custom.yaml`。本仓库已放行根目录、`windows/` 和 `llm-android/trime/` 下的此类文件。
8. Trime 不可调试，数据目录又为 `noexec`，`.so` 无法从外部放入，只能打包进 APK。更换签名须先卸载原有的 Trime，这会清空其数据目录，卸载前须备份。
9. 推理线程数不要等于 CPU 核数。任何一个线程被其他进程抢占，整批解码都要等它，会出现偶发的明显延迟。新核心已把线程数限制在核数减一以内，手机端使用 2 个线程。
10. Trime 的主题补丁文件名须为 `<主题 id>.custom.yaml`（同文风为 `tongwenfeng.trime.custom.yaml`）。Trime 只在输入法服务启动时读取主题，修改后须重启一次 Trime。按键自带的 `label` 只在中文模式下生效，英文模式显示预设标签，因此图标应修改在 `preset_keys` 中。
11. 覆盖安装 Trime 后，输入法服务须等到键盘弹出才会启动，此前发出的部署广播会丢失。应先打开任意输入框，再执行部署。

## 同步上游更新

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main && git push origin main
git checkout custom && git merge main
```

本仓库已删除用不到的双拼和九宫格方案（`double_pinyin*.schema.yaml`、`t9.schema.yaml`），以及上游给编程助手的约定 `AGENTS.md`。上游修改这些文件时，合并会报“上游已修改、本仓库已删除”的冲突，直接删除即可：

```bash
git rm double_pinyin*.schema.yaml t9.schema.yaml AGENTS.md
git commit
```

AI 重排的 Lua 脚本以 suzu-ime 的 `rime/lua/` 为唯一来源，用 `tools/sync_core.sh <suzu-ime 路径>` 同步，同步的版本记在 `lua/SUZU_IME_VERSION`。

## 自定义内容的位置

| 位置 | 内容 |
| --- | --- |
| `rime_ice.custom.yaml`、`default.custom.yaml`、`squirrel.custom.yaml` | 方案、全局和外观补丁 |
| `algebra_extra.yaml`、`tools/gen_typo_rules.py` | 模糊音与邻键容错规则 |
| `lua/ai_rerank_filter.lua`、`lua/ai_rerank_processor.lua`、`lua/personal_pairs.lua`、`lua/corpus_archive.lua`、`lua/recent_boost_filter.lua` | AI 重排、个人词对、记录归档、最近使用优先。由 suzu-ime 的 `rime/lua/` 同步而来，用 `tools/sync_core.sh` 更新，不要直接修改 |
| `lua/model_badge_filter.lua` | 整句候选的 `❖` 标记 |
| `windows/` | 小狼毫适配 |
| `llm-android/` | Android（Trime）手机端：部署脚本、手机专属覆盖配置、GBoard 风格布局补丁。Trime 的“从仓库更新”按这个路径读取，不能改名 |
| `install.sh`、`tools/verify_build.sh` | 安装与安装前自检 |

## 致谢与许可

感谢 [iDvel/rime-ice](https://github.com/iDvel/rime-ice) 及其贡献者；[zhanghaozhecn/rime-llm-rerank](https://github.com/zhanghaozhecn/rime-llm-rerank)（AI 重排的上游，署名许可，个人使用无限制）；[amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG)（万象语法模型）；[llama.cpp](https://github.com/ggml-org/llama.cpp)；[osfans/trime](https://github.com/osfans/trime)（同文输入法，GPL-3.0）及同文风主题作者暖暖；[Shizuku](https://github.com/RikkaApps/Shizuku)；以及 Rime、librime-lua、librime-octagram 的作者。

本仓库沿用上游的 GPL-3.0 许可证，见 [LICENSE](LICENSE)。模型文件和语法模型各自遵循发布方的许可。
