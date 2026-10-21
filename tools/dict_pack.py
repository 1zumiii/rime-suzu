#!/usr/bin/env python3
"""词库包：把某个 Rime 拼音词库按固定提交装进 Rime 用户目录，并生成主词典文件。

词库包是一个 Git 仓库里的词库目录（词<Tab>拼音<Tab>权重）加一个主词典文件（<name>.dict.yaml，用 import_tables 列出词库）。
packs/packs.tsv 登记每个包的来源仓库、固定提交与主词典文件名。本脚本只拷贝主词典实际导入的词库文件，
并把路径改写成目标目录，因此可以同时装多个包（各用不同目录），也可以整份替换。

用法：
  tools/dict_pack.py list
  tools/dict_pack.py install [包名] --rime-dir <Rime 用户目录> [--into cn_dicts] [--schema rime_ice] [--repo-url URL] [--no-extra]
  tools/dict_pack.py status --rime-dir <Rime 用户目录>
install 的效果：
  <rime-dir>/<into>/        主词典导入的 cn_dicts 下的文件
  <rime-dir>/<into>_cell/   主词典导入的 cn_dicts_cell 下的文件（有的话）
  <rime-dir>/<schema>.dict.yaml   改写后的主词典（词典名为 schema，使方案里的 dictionary 设置不用改）
  <rime-dir>/<into>/extra.dict.yaml   本仓库自己的补充词条（extras/extra.dict.yaml），放在导入列表最前面，重复词条以它的权重为准
  <rime-dir>/dict_pack.lock       记录装了哪个包、哪个提交
候选生成的词典目录（llm_rerank/lexicon_dir）指向 <into>，须含 base.dict.yaml。
"""
import argparse, hashlib, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKS = os.path.join(HERE, "..", "packs", "packs.tsv")
EXTRA = os.path.join(HERE, "..", "extras", "extra.dict.yaml")
CACHE = os.environ.get("SUZU_PACK_CACHE") or os.path.join(os.path.expanduser("~"), ".cache", "suzu-dict-packs")
IMPORT_RE = re.compile(r"^(\s*-\s*)(cn_dicts|cn_dicts_cell)/([^\s#]+)(.*)$")


def die(msg):
    sys.exit(f"错误：{msg}")


def load_packs():
    rows = {}
    with open(PACKS, encoding="utf-8") as f:
        head = None
        for ln in f:
            ln = ln.rstrip("\n")
            if not ln or ln.startswith("#"):
                continue
            cols = ln.split("\t")
            if head is None:
                head = cols
                continue
            rows[cols[0]] = dict(zip(head, cols))
    return rows


def fetch(pack, url):
    """把固定提交取到缓存目录（浅取），返回目录。已有则校验提交后直接用。"""
    commit = pack["commit"]
    d = os.path.join(CACHE, f"{pack['name']}-{commit[:12]}")
    def head():
        r = subprocess.run(["git", "-C", d, "rev-parse", "HEAD"], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    if head() == commit:
        return d
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    run = lambda *a: subprocess.run(["git", "-C", d, *a], check=True, capture_output=True, text=True)
    try:
        run("init", "-q")
        run("remote", "add", "origin", url)
        run("fetch", "-q", "--depth", "1", "origin", commit)
        run("checkout", "-q", "FETCH_HEAD")
    except subprocess.CalledProcessError as e:
        shutil.rmtree(d, ignore_errors=True)
        die(f"取不到 {url} 的提交 {commit[:12]}：{(e.stderr or '').strip()[:200]}")
    if head() != commit:
        die(f"取到的提交与登记的不一致（{head()[:12]} 与 {commit[:12]}）")
    return d


def check_dict(path):
    """格式检查：有 YAML 头结束标记，词条行符合下面两种写法之一（抽查前 3000 条，超过 5% 不符就拒绝）。"""
    body, n, bad = False, 0, 0
    with open(path, encoding="utf-8") as f:
        for ln in f:
            if ln.startswith("..."):
                body = True
                continue
            if not body or not ln.strip() or ln.startswith("#"):
                continue
            c = ln.rstrip("\n").split("\t")
            n += 1
            # 合法写法两种：词<Tab>拼音 [<Tab>权重]（音节数等于字数），或只有词、或词<Tab>权重（无注音，由 Rime 按字表自动注音，如雾凇的腾讯词库与 others）
            ok_coded = len(c) >= 2 and len(c[1].split()) == len(c[0])
            ok_plain = len(c) == 1 or (len(c) == 2 and c[1].strip().isdigit())
            if not (ok_coded or ok_plain):
                bad += 1
            if n >= 3000:
                break
    if not body:
        die(f"{os.path.basename(path)} 没有 YAML 头结束标记（...），不是 Rime 词典格式")
    if n == 0 or bad * 20 > n:
        die(f"{os.path.basename(path)} 抽查 {n} 条里有 {bad} 条格式不符（应为 词<Tab>拼音<Tab>权重，音节数等于字数；或只有词，或 词<Tab>权重）")


def install(a):
    packs = load_packs()
    if not a.pack:
        d = os.path.join(HERE, "..", "packs", "DEFAULT")
        a.pack = open(d, encoding="utf-8").read().strip() if os.path.isfile(d) else ""
    if a.pack not in packs:
        die(f"没有这个词库包：{a.pack}（可用：{', '.join(packs)}）")
    pack = packs[a.pack]
    if not os.path.isdir(a.rime_dir):
        die(f"Rime 用户目录不存在：{a.rime_dir}")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.into) or not re.fullmatch(r"[A-Za-z0-9_]+", a.schema):
        die("--into 与 --schema 只能含字母、数字、下划线、连字符")
    src = fetch(pack, a.repo_url or pack["repo"])
    main = os.path.join(src, pack["main_dict"])
    if not os.path.isfile(main):
        die(f"词库包里没有主词典 {pack['main_dict']}")
    # 解析主词典：未注释的导入行决定拷哪些文件
    lines = open(main, encoding="utf-8", newline=None).read().split("\n")   # 通用换行：CRLF 读成 LF
    need = []      # (源子目录，文件主名)
    out = []
    in_imports = False
    use_extra = not a.no_extra and os.path.isfile(EXTRA)
    extra_done = False
    for ln in lines:
        if re.match(r"^import_tables:\s*$", ln):
            in_imports = True
        elif in_imports and ln and not ln.startswith((" ", "\t", "#")):
            in_imports = False
        m = IMPORT_RE.match(ln) if in_imports else None
        if m and use_extra and not extra_done:
            out.append(f"{m.group(1)}{a.into}/extra   # 本仓库的补充词条，放最前面，重复词条以它的权重为准")
            extra_done = True
        if m:
            sub, stem = m.group(2), m.group(3)
            need.append((sub, stem))
            dst = a.into if sub == "cn_dicts" else a.into + "_cell"
            ln = f"{m.group(1)}{dst}/{stem}{m.group(4)}"
        elif re.match(r"^name:\s", ln):
            ln = f"name: {a.schema}"
        out.append(ln)
    if not need:
        die("主词典里没有导入任何词库（import_tables 为空）")
    for sub, stem in need:
        p = os.path.join(src, sub, stem + ".dict.yaml")
        if not os.path.isfile(p):
            die(f"主词典导入了 {sub}/{stem}，但词库包里没有这个文件")
        check_dict(p)
    if not any(s == "cn_dicts" and st == "base" for s, st in need) and not os.path.isfile(os.path.join(src, "cn_dicts", "base.dict.yaml")):
        die("词库包缺少 cn_dicts/base.dict.yaml（候选生成的词典需要它）")
    if use_extra:
        check_dict(EXTRA)
    # 目标目录整份替换
    total = 0
    for sub, dst in (("cn_dicts", a.into), ("cn_dicts_cell", a.into + "_cell")):
        d = os.path.join(a.rime_dir, dst)
        shutil.rmtree(d, ignore_errors=True)
        files = [st for s, st in need if s == sub]
        if sub == "cn_dicts":   # 候选生成固定读 base 与 ext，即使主词典没导入也一并带上
            for st in ("base", "ext"):
                if st not in files and os.path.isfile(os.path.join(src, "cn_dicts", st + ".dict.yaml")):
                    files.append(st)
        if not files:
            continue
        os.makedirs(d)
        if sub == "cn_dicts" and use_extra:
            shutil.copy(EXTRA, os.path.join(d, "extra.dict.yaml"))
        for st in files:
            shutil.copy(os.path.join(src, sub, st + ".dict.yaml"), os.path.join(d, st + ".dict.yaml"))
            total += os.path.getsize(os.path.join(d, st + ".dict.yaml"))
    text = "\n".join(out)
    target = os.path.join(a.rime_dir, a.schema + ".dict.yaml")
    with open(target, "w", encoding="utf-8", newline="\n") as f:   # Windows 上也写 LF，输出与平台无关
        f.write(text)
    with open(os.path.join(a.rime_dir, "dict_pack.lock"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"pack\t{a.pack}\ncommit\t{pack['commit']}\ninto\t{a.into}\nschema\t{a.schema}\nlicense\t{pack['license']}\n")
    print(f"已安装 {a.pack}（{pack['commit'][:12]}，{pack['license']}）：{len(need)} 个词库文件{'，含补充词条' if use_extra else ''}，{total / 1e6:.1f} MB → {a.rime_dir}/{a.into}")
    print(f"主词典 {a.schema}.dict.yaml sha256 {hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]}")


def status(a):
    p = os.path.join(a.rime_dir, "dict_pack.lock")
    if not os.path.isfile(p):
        print("没有安装词库包（没有 dict_pack.lock）")
        return
    print(open(p, encoding="utf-8").read().strip())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("list")
    i = sp.add_parser("install")
    i.add_argument("pack", nargs="?", help="词库包名，省略时用 packs/DEFAULT 里写的")
    i.add_argument("--rime-dir", required=True)
    i.add_argument("--into", default="cn_dicts")
    i.add_argument("--schema", default="rime_ice")
    i.add_argument("--repo-url")
    i.add_argument("--no-extra", action="store_true", help="不带本仓库的补充词条")
    s = sp.add_parser("status")
    s.add_argument("--rime-dir", required=True)
    a = ap.parse_args()
    if a.cmd == "list":
        for n, p in load_packs().items():
            print(f"{n}\t{p['commit'][:12]}\t{p['license']}\t{p['repo']}\t{p.get('note', '')}")
    elif a.cmd == "install":
        install(a)
    else:
        status(a)


if __name__ == "__main__":
    main()
