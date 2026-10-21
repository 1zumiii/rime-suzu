#!/usr/bin/env python3
"""dict_pack.py 的测试：用临时 Git 仓库当词库包，检查按提交取包、改写导入路径、格式检查与拒绝、整份替换。
用法：python3 -I tools/test_dict_pack.py"""
import os, subprocess, sys, tempfile, shutil, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(name, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (f"  [{extra}]" if extra and not cond else ""))
    fails += 0 if cond else 1

def sh(cwd, *a):
    return subprocess.run(a, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()

def mkpack(root, base_lines, main_extra="", cells=True):
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root + "/cn_dicts"); os.makedirs(root + "/cn_dicts_cell")
    hdr = "---\nname: x\nversion: \"1\"\nsort: by_weight\n...\n"
    open(root + "/cn_dicts/base.dict.yaml", "w", encoding="utf-8").write(hdr + base_lines)
    open(root + "/cn_dicts/ext.dict.yaml", "w", encoding="utf-8").write(hdr + "经理\tjing li\t5\n")
    open(root + "/cn_dicts/unused.dict.yaml", "w", encoding="utf-8").write(hdr + "不会\tbu hui\t1\n")
    open(root + "/cn_dicts_cell/food.dict.yaml", "w", encoding="utf-8").write(hdr + "米饭\tmi fan\t3\n")
    main = ("# Rime dictionary\n---\nname: fakepack\nversion: \"1\"\nimport_tables:\n  - cn_dicts/base     # 基础\n  - cn_dicts/ext\n"
            "  # - cn_dicts/unused\n" + ("  - cn_dicts_cell/food\n" if cells else "") + main_extra + "...\n\nA\tA\n")
    open(root + "/fakepack.dict.yaml", "w", encoding="utf-8").write(main)
    sh(root, "git", "init", "-q"); sh(root, "git", "add", "-A")
    sh(root, "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "x")
    return sh(root, "git", "rev-parse", "HEAD")

tmp = tempfile.mkdtemp(prefix="dictpack_test_")
os.environ["SUZU_PACK_CACHE"] = tmp + "/cache"
spec = importlib.util.spec_from_file_location("dict_pack", HERE + "/dict_pack.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

def set_packs(commit):
    os.makedirs(tmp + "/packs", exist_ok=True)
    open(tmp + "/packs/packs.tsv", "w", encoding="utf-8").write(
        f"name\trepo\tcommit\tlicense\tmain_dict\tnote\nfake\t{tmp}/pack\t{commit}\tGPL-3.0\tfakepack.dict.yaml\t\n")
    dp.PACKS = tmp + "/packs/packs.tsv"

class A:  # 命令行参数的替身
    def __init__(s, **k): s.__dict__.update(dict(pack="fake", into="cn_dicts", schema="rime_ice", repo_url=None, no_extra=True), **k)

rime = tmp + "/rime"; os.makedirs(rime)
c1 = mkpack(tmp + "/pack", "经理\tjing li\t100\n精力\tjing li\t90\n"); set_packs(c1)
dp.install(A(rime_dir=rime))
d = open(rime + "/rime_ice.dict.yaml", encoding="utf-8").read()
check("主词典名改成方案名", "\nname: rime_ice\n" in d and "fakepack" not in d)
check("导入路径改写，注释保留", "  - cn_dicts/base     # 基础" in d and "  - cn_dicts_cell/food" in d)
check("词库文件拷贝，只拷导入的", os.path.exists(rime + "/cn_dicts/base.dict.yaml") and os.path.exists(rime + "/cn_dicts/ext.dict.yaml")
      and not os.path.exists(rime + "/cn_dicts/unused.dict.yaml") and os.path.exists(rime + "/cn_dicts_cell/food.dict.yaml"))
check("尾部词条保留", d.rstrip().endswith("A\tA"))
check("lock 记录提交", c1 in open(rime + "/dict_pack.lock").read())

# 补充词条：放在导入列表最前面，并拷进词库目录
open(tmp + "/extra.dict.yaml", "w", encoding="utf-8").write("---\nname: extra\n...\n宝子们\tbao zi men\t1000\n")
dp.EXTRA = tmp + "/extra.dict.yaml"
dp.install(A(rime_dir=rime, into="cn_dicts_e", schema="rime_e", no_extra=False))
de = open(rime + "/rime_e.dict.yaml", encoding="utf-8").read()
imps = [l for l in de.split("\n") if l.startswith("  - ")]
check("补充词条在导入列表最前面并已拷贝", imps[0].startswith("  - cn_dicts_e/extra") and os.path.exists(rime + "/cn_dicts_e/extra.dict.yaml"), str(imps[:2]))
dp.EXTRA = tmp + "/none.yaml"
# 另装到别的目录与方案名：互不影响
dp.install(A(rime_dir=rime, into="cn_dicts_x", schema="rime_x"))
d2 = open(rime + "/rime_x.dict.yaml", encoding="utf-8").read()
check("换目录与方案名", "  - cn_dicts_x/base" in d2 and "  - cn_dicts_x_cell/food" in d2 and "\nname: rime_x\n" in d2
      and os.path.exists(rime + "/cn_dicts_x/base.dict.yaml") and os.path.exists(rime + "/cn_dicts/base.dict.yaml"))

# 整份替换：新提交里少了文件，旧文件不留
c2 = mkpack(tmp + "/pack", "教练\tjiao lian\t50\n"); set_packs(c2)
os.makedirs(rime + "/cn_dicts", exist_ok=True); open(rime + "/cn_dicts/stale.dict.yaml", "w").write("x")
dp.install(A(rime_dir=rime))
check("整份替换：旧文件被清掉，新内容生效", not os.path.exists(rime + "/cn_dicts/stale.dict.yaml")
      and "教练" in open(rime + "/cn_dicts/base.dict.yaml", encoding="utf-8").read())

def rejects(label, fn):
    try:
        fn(); check(label, False, "没有拒绝")
    except SystemExit as e:
        check(label, True)

# 格式不符：音节数与字数不一致
c3 = mkpack(tmp + "/pack", "".join(f"词{i}\tci\t1\n" for i in range(50))); set_packs(c3)
rejects("格式不符的词库被拒绝", lambda: dp.install(A(rime_dir=rime)))
# 无注音的写法（词<Tab>权重）允许：雾凇的腾讯词库就是这样
c5 = mkpack(tmp + "/pack", "经理\tjing li\t100\n", main_extra="  - cn_dicts/tencent\n"); set_packs(c5)
open(tmp + "/pack/cn_dicts/tencent.dict.yaml", "w", encoding="utf-8").write("---\nname: tencent\n...\n" + "".join(f"出国游{i}\t{i}\n" for i in range(50)))
sh(tmp + "/pack", "git", "add", "-A"); sh(tmp + "/pack", "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "tencent")
set_packs(sh(tmp + "/pack", "git", "rev-parse", "HEAD"))
dp.install(A(rime_dir=rime))
check("无注音写法被接受", os.path.exists(rime + "/cn_dicts/tencent.dict.yaml"))
# 提交号与仓库不符
set_packs("0" * 40)
rejects("取不到的提交被拒绝", lambda: dp.install(A(rime_dir=rime)))
# 主词典导入了不存在的文件
c4 = mkpack(tmp + "/pack", "经理\tjing li\t1\n", main_extra="  - cn_dicts/missing\n"); set_packs(c4)
rejects("导入了不存在的文件被拒绝", lambda: dp.install(A(rime_dir=rime)))
# 非法的目录名
set_packs(c1 if False else c4)
rejects("非法目录名被拒绝", lambda: dp.install(A(rime_dir=rime, into="../x")))
rejects("不存在的包被拒绝", lambda: dp.install(A(rime_dir=rime, pack="nope")))

shutil.rmtree(tmp, ignore_errors=True)
print(f"{fails} FAILED" if fails else "ALL PASS")
sys.exit(1 if fails else 0)
