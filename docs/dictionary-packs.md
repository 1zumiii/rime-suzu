# 词库包

词库以独立的“词库包”按固定提交安装，不纳入本仓库。替换或更新词库均由安装工具处理，无需手动复制文件或合并词库仓库的提交。

## 安装与替换

```bash
tools/dict_pack.py list                                   # 列出登记的词库包
tools/dict_pack.py install frost --rime-dir ~/Library/Rime   # 安装白霜，整份替换原有词库
tools/dict_pack.py status --rime-dir ~/Library/Rime         # 查看装的是哪个包、哪个提交
```

Android 在应用的“设置 → 词库”中下载和切换词库包，下载后校验并重新编译，切换时保留已学习的词。已下载的包保留在手机上，无需重复下载。

桌面端的 `tools/install-dev.sh` 和 `windows/install.ps1` 安装配置时会自动调用词库安装工具，包名分别用 `--pack` 和 `-Pack` 指定。省略时使用在线名录的默认包，离线回退到 `packs/DEFAULT`。首次安装须联网，并安装 Git 和 Python 3。下载内容缓存在 `~/.cache/suzu-dict-packs`。

安装后须重新部署输入法，Rime 才会重新编译词库。换包之后，个人词对基础表（`personal_pairs_base.tsv`）建议用新词库重建，因为它是按词库切词建的。

## 安装流程

1. 读取 [Suzu 在线词库名录](https://github.com/1zumiii/suzu-ime/blob/main/dicts.json)，按固定提交浅层获取词库仓库并核对提交。名录不可用时使用 `packs/packs.tsv`。
2. 读取主词典文件，只复制实际导入的词库文件，即 `import_tables` 中未注释的条目。
3. 检查词库格式：词条须为“词、拼音、权重”（拼音音节数等于字数），或只有词、或“词、权重”（无注音，由 Rime 按字表自动注音）。抽查的不符合比例超过 5% 就拒绝安装。
4. 把词库放进用户目录的 `cn_dicts/`（有细胞词库时另放 `cn_dicts_cell/`），生成 `rime_ice.dict.yaml`，并把本仓库的补充词条放在导入列表最前面。
5. 写入 `dict_pack.lock`，记录包名与提交。标准方案直接显示包名，例如“白霜”或“雾凇”，方案 ID 仍为 `rime_ice`。

`--into` 与 `--schema` 可指定另一个目录和方案名，用来同时装多个包。例如 `--into cn_dicts_frost --schema rime_frost` 装一份白霜，再复制一份方案文件，把其中的 `dictionary` 改成 `rime_frost`，并在该方案的补丁里设 `llm_rerank/lexicon_dir: cn_dicts_frost`。这样两个方案可以在输入法的方案菜单里来回切换，候选生成的词典也随方案切换，模型不用重新加载。

## 补充词条

`extras/extra.dict.yaml` 是本仓库自己的词条（网络用语等），安装时拷进词库目录并放在导入列表最前面。Rime 在重复词条上以最上面的权重为准，所以这里的权重优先。候选生成读词典目录里的 `base`、`ext` 和 `extra`，补充词条因此也会出现在简拼补词里。

补充词条的权重按雾凇的量级定（1000、3000）。换用权重量级不同的词库时，需要核对这些权重是否合适。

## 新增词库包

在 `packs/packs.tsv` 登记包名、仓库地址、完整的 40 位提交、许可证和主词典文件名。该表用于构建词库包和离线安装。生成 ZIP 后，把地址、大小、SHA-256、显示名和桌面源信息登记到在线名录。新条目可由现有 Android 版本直接读取。词库仓库须满足以下条件。

- 根目录有主词典文件，用 `import_tables` 导入 `cn_dicts/` 与 `cn_dicts_cell/` 下的词库。
- `cn_dicts/base.dict.yaml` 存在，候选生成要读它。
- 词条格式符合上面第 3 点。

只验证过雾凇和白霜。符合上面条件的标准 Rime 格式词库理论上可以直接登记使用，但词库的格式细节（辅助码列、非常规列顺序等）和权重量级各不相同，未验证的包要先确认编译与输入正常。

新词库包须先完成小样本验证：安装后用 `rime_deployer --build` 编译，确认词库表已生成且输入时有候选，再运行评测。
