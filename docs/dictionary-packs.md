# 词库包

词库不放在本仓库里，而是以“词库包”的形式按固定提交安装。这样换用别的词库、跟进词库更新，不需要手动搬文件，也不用合并词库仓库的提交。

## 安装与替换

```bash
tools/dict_pack.py list                                   # 列出登记的词库包
tools/dict_pack.py install frost --rime-dir ~/Library/Rime   # 安装白霜，整份替换原有词库
tools/dict_pack.py status --rime-dir ~/Library/Rime         # 查看装的是哪个包、哪个提交
```

`tools/install-dev.sh`、`windows/install.ps1` 和 `llm-android/deploy_trime.sh` 安装配置时会自动调用它，包名用 `--pack`（`tools/install-dev.sh`）、`-Pack`（Windows）或环境变量 `PACK`（Android）指定，省略时用 `packs/DEFAULT`。首次安装需要联网，并要求已安装 git 与 Python 3，下载的内容缓存在 `~/.cache/suzu-dict-packs`。

安装后须重新部署输入法，Rime 才会重新编译词库。换包之后，个人词对基础表（`personal_pairs_base.tsv`）建议用新词库重建，因为它是按词库切词建的。

## 安装做了什么

1. 按 `packs/packs.tsv` 里的固定提交浅取词库仓库，核对取到的提交。
2. 读词库仓库里的主词典文件，只拷贝它实际导入（`import_tables` 里未注释）的词库文件。
3. 检查词库格式：词条须为“词、拼音、权重”（拼音音节数等于字数），或只有词、或“词、权重”（无注音，由 Rime 按字表自动注音）。抽查的不符合比例超过 5% 就拒绝安装。
4. 把词库放进用户目录的 `cn_dicts/`（有细胞词库时另放 `cn_dicts_cell/`），生成 `rime_ice.dict.yaml`，并把本仓库的补充词条放在导入列表最前面。
5. 写入 `dict_pack.lock`，记录包名与提交。

`--into` 与 `--schema` 可指定另一个目录和方案名，用来同时装多个包。例如 `--into cn_dicts_frost --schema rime_frost` 装一份白霜，再复制一份方案文件，把其中的 `dictionary` 改成 `rime_frost`，并在该方案的补丁里设 `llm_rerank/lexicon_dir: cn_dicts_frost`。这样两个方案可以在输入法的方案菜单里来回切换，候选生成的词典也随方案切换，模型不用重新加载。

## 补充词条

`extras/extra.dict.yaml` 是本仓库自己的词条（网络用语等），安装时拷进词库目录并放在导入列表最前面。Rime 在重复词条上以最上面的权重为准，所以这里的权重优先。候选生成读词典目录里的 `base`、`ext` 和 `extra`，补充词条因此也会出现在简拼补词里。

补充词条的权重按雾凇的量级定（1000、3000）。换用权重量级不同的词库时，需要核对这些权重是否合适。

## 新增词库包

在 `packs/packs.tsv` 里加一行：名字、仓库地址、完整的 40 位提交、许可证、主词典文件名。词库仓库须满足：

- 根目录有主词典文件，用 `import_tables` 导入 `cn_dicts/` 与 `cn_dicts_cell/` 下的词库。
- `cn_dicts/base.dict.yaml` 存在，候选生成要读它。
- 词条格式符合上面第 3 点。

只验证过雾凇和白霜。符合上面条件的标准 Rime 格式词库理论上可以直接登记使用，但词库的格式细节（辅助码列、非常规列顺序等）和权重量级各不相同，未验证的包要先确认编译与输入正常。

新词库包先用小样本验证再放量：安装后用 `rime_deployer --build` 编译，确认词库表生成、输入时有候选，再跑评测。
