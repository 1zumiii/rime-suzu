# 其他功能

## 个人词对与纠错记忆

个人词对记录“前一个词 → 当前词”的使用次数，同样的搭配再次出现时优先。计数带时间衰减（14 天衰减到约 1/e），也参与 AI 重排的融合打分（`llm_rerank/pair_gamma`，默认 1.5，设为 0 关闭）。

- 记录保存在用户目录的 `recent_pairs.tsv`，内容为相邻上屏词的明文（最多 6000 条，保留 90 天）。删除该文件并重新部署即可清空。
- 只记含中文的词，不记英文和数字串；超过 8 个字的整句不记。
- “前一个词”只在上一次上屏后 20 秒内有效；退格、方向键、回车之后失效。
- 纠错记忆：在“前一个词 + 输入的拼音”这个情境下记住所选的词，选了非首位的权重更大。同样的情境再出现时，选过的词优先（`llm_rerank/corr_gamma`，默认 3.0，0 关闭）。
- 开关为 `recent_boost_filter/pairs`（默认 true）。提升阈值为 `min_pair`（默认 1.5，约需同一搭配重复出现两次，避免单次误选被固化）。

## 最近使用优先

最近 72 小时内上屏过的词会提升到第 2 个候选位置（最多 2 个词），置顶词仍在最前。参数在 `rime_ice.custom.yaml` 的 `recent_boost_filter`（`window_hours`、`idx`、`max_boost` 等）。记录保存在用户目录的 `recent_words.tsv`，内容为上屏词的明文（默认最多 3000 条）。原有的词频学习（userdb）不变，本功能是在其基础上的补充。

## 本机记录一览

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

## 选词统计

选词统计默认关闭，用来以真实输入评估重排是否有帮助。每次选词在 `select_stats.tsv` 里记一行纯数字：时间戳、AI 开关、模型、输入字母数、参与重排的候选数、所选候选在原顺序和最终顺序里的位次、上文长度档、候选字数、候选类型。不含任何输入的文字、拼音和候选文字。

- 开启：在用户目录新建空文件 `select_stats.enabled`，新开的输入会话生效。删除该文件即停止，删除 `select_stats.tsv` 即清空。
- 汇总：`python3 tools/select_stats_report.py select_stats.tsv`（脚本在 [suzu-ime](https://github.com/1zumiii/suzu-ime/blob/main/tools/select_stats_report.py)），给出原顺序第一位被选中的比例与重排后的比例、重排救回与帮倒忙的次数，并按模型、输入长度、上文长度分组。

## 语法模型

本仓库配置了万象语法模型 `wanxiang-lts-zh-hans.gram`（约 379 MB），用于改善整句输入时的同音字选择，鼠须管自带 octagram 插件。模型文件不在仓库中，须自行从 [amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG/releases) 下载，放入 `~/Library/Rime/`。缺少该文件时，相关配置会被忽略，不影响使用。整句候选带 `❖` 标记（`model_badge_filter.lua`）。

## 模糊音与误触容错

模糊音开启了平翘舌（z/zh、c/ch、s/sh）和前后鼻音（an/ang、en/eng、in/ing）。规则在 `algebra_extra.yaml`，由 `tools/gen_typo_rules.py` 生成。需要关闭某一组时，在脚本中注释对应行并重新生成。

相邻按键误触容错只处理 4 个字母及以上的音节，末字母只允许换成 i、u、v，避免把两个字吞成一个。邻键替换类错拼的首选命中率由 0.7% 提高到 32.9%，吞字比例约 0.3%～2.6%。数据与取舍见 [typo-tolerance.md](typo-tolerance.md)。

## 其他小改动

| 改动 | 说明 |
| --- | --- |
| 冷词降频 | 启用上游自带的 `cold_word_drop`：`Control+j` 降频，`Control+x` 隐藏，`Control+d` 强制删词 |
| 英文、自定义短语调频 | `melt_eng` 打开用户词典，`custom_phrase` 改为 `tabledb`（Rime 会回写 `custom_phrase.txt`） |
| 中英混输自动空格 | 启用上游自带的 `cn_en_spacer`，`VIP中P` → `VIP 中 P` |
| 每页候选 5 个 | 7 个时短词容易折到第二行 |
| 方案列表 | 只保留 `rime_ice`（全拼）。九宫格和各种双拼方案文件已从本仓库删除，需要时从上游取回，并在 `default.custom.yaml` 的 `schema_list` 中添加 |
| 外观 | `squirrel.custom.yaml`：微信键盘配色、横排候选、OpenSans 字体 |
