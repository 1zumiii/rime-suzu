# 维护说明

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
