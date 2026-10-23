#!/usr/bin/env python3
"""打一键安装包：把配置、词库包、Suzu 模型、推理核心和安装脚本装进一个 zip，朋友解压后运行安装脚本即可，
不需要 git、Python 或自己编译。

用法：
  tools/make_bundle.py macos   --core <rime_llm.so> --model <suzu.gguf> --vocab <suzu.vocab.txt> [--out dist] [--version X]
  tools/make_bundle.py windows --core <rime_llm.dll> --model ... --vocab ...
  tools/make_bundle.py android --apk <trime.apk> --daemon <rimellmd> --model ... --vocab ... [--rimellmctl <rimellmctl.sh>]
可选：--pack <词库包名>（默认 packs/DEFAULT）、--repo-url（词库包来源仓库的本地路径，省去联网）。

包里不含任何统计开关文件（*.enabled）：选词统计、语料、输入事件流都是用户目录里有对应的空文件才开启，安装脚本不创建它们，所以默认全部关闭。
输出：<out>/suzu-<平台>.zip 与同名 .sha256（文件名不带版本，版本在包内的 VERSION 里）。
"""
import argparse, datetime, hashlib, os, re, shutil, stat, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))

COMMON_EXCLUDE_DIRS = {"docs", "tools", "packs", "extras", "others", "tests", ".github", "build", "windows", "llm-android"}
COMMON_EXCLUDE_FILES = {".gitignore", "README.md", "install.sh", "install.ps1", "squirrel.yaml", "squirrel.custom.yaml", "weasel.yaml", "LICENSE"}


def die(msg):
    sys.exit(f"错误：{msg}")


def sh(*a, cwd=None):
    return subprocess.run(a, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def export_config(dst):
    """用 git archive 导出已提交的内容（不含未提交的改动与被忽略的个人文件），再按平台无关的规则筛选。"""
    if sh("git", "status", "--porcelain", "--untracked-files=no", cwd=REPO):
        print("警告：工作区有未提交的改动，打包使用已提交的版本（HEAD）", file=sys.stderr)
    tmp = tempfile.mkdtemp(prefix="suzu_bundle_src_")
    tar = os.path.join(tmp, "src.tar")
    sh("git", "archive", "--format=tar", "-o", tar, "HEAD", cwd=REPO)
    ex = os.path.join(tmp, "x")
    os.makedirs(ex)
    sh("tar", "-xf", tar, "-C", ex)
    os.makedirs(dst, exist_ok=True)
    for name in os.listdir(ex):
        p = os.path.join(ex, name)
        if os.path.isdir(p) and name in COMMON_EXCLUDE_DIRS:
            continue
        if os.path.isfile(p) and name in COMMON_EXCLUDE_FILES:
            continue
        (shutil.copytree if os.path.isdir(p) else shutil.copy2)(p, os.path.join(dst, name))
    return ex   # 调用方还要从中取 windows/、llm-android/ 里的文件，用完后由系统清理临时目录


def install_pack(payload, pack, repo_url):
    cmd = [sys.executable, "-I", os.path.join(HERE, "dict_pack.py"), "install"]
    if pack:
        cmd.append(pack)
    cmd += ["--rime-dir", payload]
    if repo_url:
        cmd += ["--repo-url", repo_url]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        die("词库包安装失败：" + (r.stderr or r.stdout).strip()[-300:])
    print(r.stdout.strip().splitlines()[0])


def copy_model(payload, model, vocab):
    for src, name in ((model, "suzu.gguf"), (vocab, "suzu.vocab.txt")):
        if not os.path.isfile(src):
            die(f"找不到 {src}")
        shutil.copy2(src, os.path.join(payload, name))
    lines = sum(1 for _ in open(vocab, encoding="utf-8"))
    if lines < 8:
        die("词表行数过少，文件不对")


def put_exec(zf, src, arcname):
    zi = zipfile.ZipInfo(arcname)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = (stat.S_IFREG | 0o755) << 16
    zi.date_time = datetime.datetime.now().timetuple()[:6]
    with open(src, "rb") as f:
        zf.writestr(zi, f.read())


def zip_dir(root, zip_path, top, exec_names):
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for base, dirs, files in os.walk(root):
            dirs.sort()
            for fn in sorted(files):
                p = os.path.join(base, fn)
                rel = os.path.relpath(p, root).replace(os.sep, "/")
                arc = f"{top}/{rel}"
                if fn in exec_names or rel in exec_names:
                    put_exec(zf, p, arc)
                else:
                    zf.write(p, arc)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("platform", choices=["macos", "windows", "android"])
    ap.add_argument("--core", help="推理核心：macOS 的 rime_llm.so，Windows 的 rime_llm.dll")
    ap.add_argument("--apk", help="android：改版 Trime 的 APK")
    ap.add_argument("--daemon", help="android：守护进程 rimellmd（arm64）")
    ap.add_argument("--rimellmctl", help="android：rimellmctl.sh（默认取 suzu-ime 同级目录或 SUZU_IME 环境变量里的）")
    ap.add_argument("--model", required=True)
    ap.add_argument("--vocab", required=True)
    ap.add_argument("--pack", default="")
    ap.add_argument("--repo-url", default="")
    ap.add_argument("--version", default="")
    ap.add_argument("--out", default=os.path.join(REPO, "dist"))
    a = ap.parse_args()

    ver = a.version or ("preview-" + datetime.date.today().strftime("%Y%m%d"))
    arch = {"macos": "macos-arm64", "windows": "windows-x64", "android": "android-arm64"}[a.platform]
    top = f"suzu-{arch}-{ver}"
    os.makedirs(a.out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="suzu_bundle_")
    root = os.path.join(work, top)
    payload = os.path.join(root, "payload")
    os.makedirs(payload)

    src = export_config(payload)
    install_pack(payload, a.pack, a.repo_url)
    copy_model(payload, a.model, a.vocab)
    exec_names = set()

    inst = os.path.join(REPO, "install", a.platform)
    if not os.path.isdir(inst):
        die(f"缺少安装脚本目录 {inst}")

    if a.platform == "macos":
        if not a.core:
            die("macos 需要 --core rime_llm.so")
        out = subprocess.run(["file", a.core], capture_output=True, text=True).stdout
        if "arm64" not in out:
            die(f"{a.core} 不是 arm64 的 Mach-O：{out.strip()}")
        os.makedirs(os.path.join(root, "core"))
        shutil.copy2(a.core, os.path.join(root, "core", "rime_llm.so"))
        # 个人外观补丁不带；鼠须管自带的 squirrel.yaml 用系统的
    elif a.platform == "windows":
        if not a.core:
            die("windows 需要 --core rime_llm.dll")
        os.makedirs(os.path.join(root, "core"))
        shutil.copy2(a.core, os.path.join(root, "core", "rime_llm.dll"))
        # Windows 专用的配置补丁（光标上文接入层 ai_rerank_app_ctx.lua 是共用的，已在 lua/ 里）
        shutil.copy2(os.path.join(src, "windows", "rime_ice.custom.yaml"), os.path.join(payload, "rime_ice.custom.yaml"))
    else:
        if not (a.apk and a.daemon):
            die("android 需要 --apk 与 --daemon")
        os.makedirs(os.path.join(root, "android"))
        shutil.copy2(a.apk, os.path.join(root, "android", "trime.apk"))
        shutil.copy2(a.daemon, os.path.join(root, "android", "rimellmd"))
        ctl = a.rimellmctl or os.path.join(os.environ.get("SUZU_IME", os.path.join(REPO, "..", "suzu-ime")), "android", "daemon", "rimellmctl.sh")
        if not os.path.isfile(ctl):
            die(f"找不到 rimellmctl.sh：{ctl}（用 --rimellmctl 指定）")
        shutil.copy2(ctl, os.path.join(root, "android", "rimellmctl.sh"))
        exec_names.add("android/rimellmctl.sh")
        # 手机专属的覆盖配置：*.overlay.yaml 追加到同名 .custom.yaml 末尾；主题补丁 *.custom.yaml 直接放入用户目录
        tdir = os.path.join(src, "llm-android", "trime")
        for fn in sorted(os.listdir(tdir)):
            p = os.path.join(tdir, fn)
            if fn.endswith(".overlay.yaml"):
                base = fn[: -len(".overlay.yaml")]
                tgt = os.path.join(payload, base + ".custom.yaml")
                if not os.path.isfile(tgt):
                    die(f"{fn} 没有对应的 {base}.custom.yaml")
                with open(tgt, "a", encoding="utf-8", newline="\n") as f:
                    t = open(tgt, encoding="utf-8").read()
                    if not t.endswith("\n"):
                        f.write("\n")
                    f.write(open(p, encoding="utf-8").read())
            elif fn.endswith(".custom.yaml"):
                shutil.copy2(p, os.path.join(payload, fn))
        # 手机用不到的文件
        for n in ("symbols_caps_v.yaml",):
            pass

    for fn in os.listdir(inst):
        shutil.copy2(os.path.join(inst, fn), os.path.join(root, fn))
        if fn.endswith((".sh", ".command")):
            exec_names.add(fn)
    shutil.copy2(os.path.join(REPO, "LICENSE"), os.path.join(root, "LICENSE"))

    # 版本与来源
    try:
        git = sh("git", "rev-parse", "--short", "HEAD", cwd=REPO)
    except Exception:
        git = "unknown"
    lock = open(os.path.join(payload, "dict_pack.lock"), encoding="utf-8").read().replace("\t", " ").replace("\n", "；")
    with open(os.path.join(root, "VERSION"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"suzu {arch} {ver}\nrime-suzu {git}\n{open(os.path.join(payload, 'lua', 'SUZU_IME_VERSION'), encoding='utf-8').read().strip()}\n词库包 {lock}\n模型 Suzu-2.4（见 payload/suzu.gguf）\n")
    with open(os.path.join(root, "NOTICE.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(NOTICE)

    zip_path = os.path.join(a.out, f"suzu-{arch}.zip")   # 文件名不带版本，一行安装用固定地址下载；版本写在包内的 VERSION 和顶层目录名里
    zip_dir(root, zip_path, top, exec_names)
    digest = sha256(zip_path)
    with open(zip_path + ".sha256", "w", encoding="utf-8", newline="\n") as f:
        f.write(f"{digest}  {os.path.basename(zip_path)}\n")
    shutil.rmtree(work, ignore_errors=True)
    print(f"已生成 {zip_path}（{os.path.getsize(zip_path) / 1e6:.1f} MB）")
    print(f"sha256 {digest}")


NOTICE = """本安装包的组成与许可：
- 配置与脚本：rime-suzu（GPL-3.0），方案与配置结构来自雾凇拼音 rime-ice（GPL-3.0）。
- 词库：词库包 ice，来自 iDvel/rime-ice（GPL-3.0），另有本项目的补充词条（GPL-3.0）。
- 模型：Suzu-2.4（CC BY-SA 4.0），https://huggingface.co/IzumiThe3rd/Suzu-2.4 ；训练数据与许可见该页面。
- 推理核心：suzu-ime（GPL-3.0），https://github.com/1zumiii/suzu-ime ；使用 llama.cpp（MIT）。
- 同文输入法 Trime（Android 包，GPL-3.0）：https://github.com/osfans/trime ，改版补丁在 suzu-ime 仓库。
- 万象语法模型 wanxiang-lts-zh-hans.gram（CC BY 4.0，作者 amzxyz）：不在安装包里，Windows 安装时可选从 https://github.com/amzxyz/rime-wanxiang-data 下载。
完整的署名与许可见各仓库的 NOTICE 与 LICENSE。
"""

if __name__ == "__main__":
    main()
