#!/usr/bin/env python3
"""按手机上选定的方案整理部署暂存区，由 deploy_trime.sh 调用。

修复只写在 rime_ice 的方案、补丁和 overlay 里，其他方案部署时从它们生成，所以修复不绑定某个方案：
  1. default.custom.yaml 的 schema_list 换成手机现有的，部署不改变用户选定的方案；
  2. 手机上不记忆 ascii_punct（误开后中文模式也出半角标点，Trime 还会忽略键上的标签）；
  3. 对 schema_list 里除 rime_ice 外的方案，生成 <方案>.schema.yaml 和 <方案>.custom.yaml。
     方案显示名和 llm_rerank/lexicon_dir 沿用手机上的值；词典 <方案>.dict.yaml 必须已在手机上。

用法：phone_schemas.py <暂存区目录> <手机上的 Rime 目录>
标准输出第一行是当前方案，供部署脚本等待编译产物。环境变量 ADB 指定 adb 命令。
"""
import os
import re
import subprocess
import sys

BASE = "rime_ice"
SCHEMA_RE = re.compile(r"^[A-Za-z0-9_]+$")


def phone_text(dest, name):
    r = subprocess.run([os.environ.get("ADB", "adb"), "shell", f"cat {dest}/{name} 2>/dev/null"], capture_output=True)
    return r.stdout.decode("utf-8", "replace").replace("\r\n", "\n") if r.returncode == 0 else ""


def phone_schemas(text):
    """取 schema_list 里的方案名。支持 - schema: x 和 - {schema: x} 两种写法。"""
    m = re.search(r"^\s*[\"']?schema_list[\"']?:\s*\n((?:\s*-\s*.*\n?)+)", text, re.M)
    names = re.findall(r"schema:\s*([A-Za-z0-9_]+)", m.group(1)) if m else []
    return [n for n in names if SCHEMA_RE.match(n)]


def rewrite_default(stage, schemas):
    path = os.path.join(stage, "default.custom.yaml")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    block = "".join(f"    - schema: {s}\n" for s in schemas)
    text, n = re.subn(r"^(  schema_list:\n)(?:    - .*\n?)+", lambda m: m.group(1) + block, text, flags=re.M)
    if n != 1:
        sys.exit("default.custom.yaml 里没有找到 schema_list")
    text, n = re.subn(r"^    - ascii_punct\n", "", text, flags=re.M)
    if n != 1:
        sys.exit("default.custom.yaml 的 save_options 里没有找到 ascii_punct")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def derive(stage, dest, schema):
    if not phone_text(dest, f"{schema}.dict.yaml"):
        sys.exit(f"手机上没有 {schema}.dict.yaml，无法生成方案 {schema}")
    with open(os.path.join(stage, f"{BASE}.schema.yaml"), encoding="utf-8") as f:
        text = f.read()
    text, n = re.subn(rf"^(\s*schema_id:\s*){BASE}\b", rf"\g<1>{schema}", text, flags=re.M)
    if n != 1:
        sys.exit("基座方案里没有找到 schema_id")
    # 只换主翻译器（第一处）。后面反查用的 dictionary 另有用途，保持不变
    text, n = re.subn(rf"^(\s*dictionary:\s*){BASE}\b", rf"\g<1>{schema}", text, count=1, flags=re.M)
    if n != 1:
        sys.exit("基座方案里没有找到 dictionary")
    name = re.search(r"^\s*name:\s*(.+?)\s*$", phone_text(dest, f"{schema}.schema.yaml"), re.M)
    if name:
        text, n = re.subn(r"^(\s*name:\s*).*$", lambda m: m.group(1) + name.group(1), text, count=1, flags=re.M)
    with open(os.path.join(stage, f"{schema}.schema.yaml"), "w", encoding="utf-8") as f:
        f.write(text)

    with open(os.path.join(stage, f"{BASE}.custom.yaml"), encoding="utf-8") as f:
        custom = f.read()
    lex = re.findall(r"^\s*llm_rerank/lexicon_dir:\s*([A-Za-z0-9_-]+)", phone_text(dest, f"{schema}.custom.yaml"), re.M)
    if lex:
        if not custom.endswith("\n"):
            custom += "\n"
        custom += f"  llm_rerank/lexicon_dir: {lex[-1]}\n"
    with open(os.path.join(stage, f"{schema}.custom.yaml"), "w", encoding="utf-8") as f:
        f.write(custom)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    stage, dest = sys.argv[1:]
    schemas = phone_schemas(phone_text(dest, "default.custom.yaml")) or [BASE]
    rewrite_default(stage, schemas)
    for s in schemas:
        if s != BASE:
            derive(stage, dest, s)
    print(schemas[0])


if __name__ == "__main__":
    main()
