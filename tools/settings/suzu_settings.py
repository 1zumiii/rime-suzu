#!/usr/bin/env python3
"""Suzu 设置页：在浏览器里调整鼠须管 / 小狼毫上的 Suzu 配置，改完一键重新部署。

用法：
  python3 tools/settings/suzu_settings.py [--rime-dir 目录] [--schema rime_ice] [--port 8767] [--no-browser]

设计：
- 只写自己的文件 suzu_settings.yaml（Rime 补丁格式），并在 <方案>.custom.yaml 的 patch 末尾加一行
  __patch: suzu_settings:/patch? 引用它。手写的 custom.yaml 其余内容（含注释）不改；设置文件不存在时部署照常。
- 生效值读编译产物 build/<方案>.schema.yaml，网页上同时显示“当前生效”和“本页覆盖”。
- 候选映射直接读写 emoji_custom.txt，格式与安卓设置页、lua/emoji_custom.lua 一致，几秒内生效，无须部署。
- 词库包切换调用同目录上一级的 dict_pack.py。
- 只监听 127.0.0.1；校验 Host 头；写操作须带启动时生成的随机令牌。只用 Python 标准库。
"""
import argparse
import http.server
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SETTINGS_FILE = "suzu_settings.yaml"
HOOK = "__patch: suzu_settings:/patch?"
EMOJI_FILE = "emoji_custom.txt"
EMOJI_HEADER = "# 候选映射：每行“键<Tab>候选”，候选可以是表情或任意文字，多个用空格隔开。键全是小写字母时按拼音匹配输入，否则按词匹配候选。\n"

# 网页上可调的参数：配置路径、类型、范围、标题、说明。默认值以编译产物里的生效值为准。
FIELDS = [
    {"group": "AI 排序", "path": "llm_rerank/unified/top_gate", "type": "float", "min": 0, "max": 10, "step": 0.1,
     "label": "首位门控",
     "help": "模型把首位换成别的词时，新首位的模型分要比原首位高出这么多才换。调大更保守，0 为关闭。"},
    {"group": "AI 排序", "path": "llm_rerank/unified/alpha", "type": "float", "min": 0, "max": 2, "step": 0.01,
     "label": "名次先验系数",
     "help": "词库原顺序在总分里的权重。取很小的值即可，调大后更接近不用模型时的顺序。"},
    {"group": "AI 排序", "path": "llm_rerank/max_candidates", "type": "int", "min": 2, "max": 20, "step": 1,
     "label": "参与重排的候选数",
     "help": "词库前几个候选交给模型打分。同音字多时正确的字常在第 6 到 8 位，候选太少会排不进来。"},
    {"group": "AI 排序", "path": "llm_rerank/stage2", "type": "bool",
     "label": "四字两阶段",
     "help": "四个字的输入拆成两个两字词分别排序再拼接。方案菜单里的“单段/两段”开关也要开着才生效。"},
    {"group": "个人习惯", "path": "llm_rerank/pair_gamma", "type": "float", "min": 0, "max": 5, "step": 0.1,
     "label": "个人词对系数",
     "help": "前一个词到当前词的使用习惯在总分里的权重，0 为关闭。"},
    {"group": "个人习惯", "path": "llm_rerank/freq_beta", "type": "float", "min": 0, "max": 5, "step": 0.1,
     "label": "词频系数",
     "help": "本次会话里用过的词在总分里的权重。"},
    {"group": "最近用过的词", "path": "recent_boost_filter/idx", "type": "int", "min": 1, "max": 9, "step": 1,
     "label": "提升到第几位",
     "help": "最近用过的词提升到候选的第几个位置，1 为最前面。"},
    {"group": "最近用过的词", "path": "recent_boost_filter/window_hours", "type": "int", "min": 1, "max": 720, "step": 1,
     "label": "时间窗口（小时）",
     "help": "多少小时内用过算“最近”。"},
    {"group": "最近用过的词", "path": "recent_boost_filter/max_boost", "type": "int", "min": 0, "max": 5, "step": 1,
     "label": "最多提升几个词",
     "help": "每次最多提升几个最近用过的词，0 为不提升。"},
    {"group": "最近用过的词", "path": "recent_boost_filter/min_pair", "type": "float", "min": 0, "max": 10, "step": 0.1,
     "label": "词对提升阈值",
     "help": "词对计数至少多大才提升。约需重复出现两次才达到 1.5，单次偶然搭配不提升。"},
]
FIELD_BY_PATH = {f["path"]: f for f in FIELDS}


# ---------------------------------------------------------------- 平台

def default_rime_dir():
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Rime"
    if os.name == "nt":
        return Path(os.environ.get("APPDATA", "")) / "Rime"
    return Path.home() / ".local" / "share" / "fcitx5" / "rime"


def frontend_name():
    if sys.platform == "darwin":
        return "squirrel"
    if os.name == "nt":
        return "weasel"
    return "unknown"


def log_dir():
    tmp = os.environ.get("TMPDIR") or os.environ.get("TEMP") or "/tmp"
    return Path(tmp) / f"rime.{frontend_name()}"


def deploy_command():
    """返回触发重新部署的命令；找不到时返回 None。小狼毫未在干净环境上验证。"""
    if sys.platform == "darwin":
        exe = Path("/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel")
        return [str(exe), "--reload"] if exe.exists() else None
    if os.name == "nt":
        roots = [os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramFiles(x86)", "")]
        for root in roots:
            if not root:
                continue
            hits = sorted(Path(root, "Rime").glob("weasel-*/WeaselDeployer.exe"))
            if hits:
                return [str(hits[-1]), "/deploy"]
    return None


# ---------------------------------------------------------------- 最小 YAML 读取（只读块状映射里的标量）

def _strip_comment(s):
    out, q = [], None
    for i, ch in enumerate(s):
        if q:
            out.append(ch)
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            out.append(ch)
        elif ch == "#" and (i == 0 or s[i - 1] in " \t"):
            break
        else:
            out.append(ch)
    return "".join(out).rstrip()


def _unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def yaml_scalars(text):
    """把块状 YAML 里的“键: 标量”展开成 {路径: 字符串}。列表、流式写法和多行字符串跳过。"""
    out, stack = {}, []   # stack: [(缩进, 键)]
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if not line.strip() or line.lstrip().startswith("- ") or line.strip() == "-":
            continue
        indent = len(line) - len(line.lstrip(" "))
        body = line.strip()
        m = re.match(r'^("[^"]*"|\'[^\']*\'|[^:]+?)\s*:(?:\s+(.*))?$', body)
        if not m:
            continue
        key, val = _unquote(m.group(1)), (m.group(2) or "").strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        path = "/".join([k for _, k in stack] + [key])
        if val == "" or val in ("|", ">"):
            stack.append((indent, key))
        elif not val.startswith(("{", "[")):
            out[path] = _unquote(val)
    return out


def parse_value(field, s):
    if s is None:
        return None
    t = field["type"]
    try:
        if t == "bool":
            if s.lower() in ("true", "yes", "on"):
                return True
            if s.lower() in ("false", "no", "off"):
                return False
            return None
        if t == "int":
            return int(float(s))
        return float(s)
    except ValueError:
        return None


def check_value(field, v):
    """校验网页提交的值，合法时返回规范化的值，否则抛 ValueError。"""
    t = field["type"]
    if t == "bool":
        if isinstance(v, bool):
            return v
        raise ValueError(f"{field['label']} 须为开或关")
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError(f"{field['label']} 须为数字")
    if t == "int":
        if v != int(v):
            raise ValueError(f"{field['label']} 须为整数")
        v = int(v)
    else:
        v = float(v)
    if not (field["min"] <= v <= field["max"]):
        raise ValueError(f"{field['label']} 须在 {field['min']} 到 {field['max']} 之间")
    return v


def fmt_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(round(v, 6))
    return str(v)


# ---------------------------------------------------------------- 设置文件与接入

class RimeDir:
    def __init__(self, root, schema):
        self.root = Path(root)
        self.schema = schema

    @property
    def custom(self):
        return self.root / f"{self.schema}.custom.yaml"

    @property
    def settings(self):
        return self.root / SETTINGS_FILE

    @property
    def built_schema(self):
        return self.root / "build" / f"{self.schema}.schema.yaml"

    # --- 接入
    def hook_state(self):
        """'ok'：已接入；'missing'：可自动接入；'manual'：custom.yaml 结构特殊，须手动接入。"""
        if not self.custom.exists():
            return "missing"
        text = self.custom.read_text(encoding="utf-8")
        if re.search(r"^\s+__patch:\s*suzu_settings:/patch\??\s*$", text, re.M):
            return "ok"
        return "missing" if self._hook_insert_point(text) is not None else "manual"

    @staticmethod
    def _hook_insert_point(text):
        """找 patch: 映射的子项缩进。要求 patch 是最后一个顶层键，且其中没有别的 __patch。"""
        lines = text.splitlines()
        top = [i for i, l in enumerate(lines) if l and not l[0].isspace() and not l.startswith("#")]
        if not top or not re.match(r"^patch:\s*(#.*)?$", lines[top[-1]]):
            return None
        child = None
        for l in lines[top[-1] + 1:]:
            if l.strip() and not l.lstrip().startswith("#"):
                child = len(l) - len(l.lstrip(" "))
                break
        if child is None or child == 0:
            child = 2
        body = "\n".join(lines[top[-1] + 1:])
        if re.search(r"^\s+__patch\s*:", body, re.M):
            return None
        return child

    def ensure_hook(self):
        state = self.hook_state()
        if state == "ok":
            return "ok"
        if state == "manual":
            raise RuntimeError(f"{self.custom.name} 的结构无法自动接入，请在 patch: 下手动加一行：{HOOK}")
        if not self.custom.exists():
            write_atomic(self.custom, f"# 由 Suzu 设置页创建\npatch:\n  {HOOK}\n")
            return "created"
        text = self.custom.read_text(encoding="utf-8")
        indent = self._hook_insert_point(text)
        if not text.endswith("\n"):
            text += "\n"
        text += f"\n{' ' * indent}# Suzu 设置页的覆盖值（{SETTINGS_FILE}），文件不存在时不影响部署\n{' ' * indent}{HOOK}\n"
        backup = self.custom.with_name(self.custom.name + ".bak-before-settings")
        if not backup.exists():
            backup.write_text(self.custom.read_text(encoding="utf-8"), encoding="utf-8")
        write_atomic(self.custom, text)
        return "added"

    # --- 覆盖值
    def overrides(self):
        if not self.settings.exists():
            return {}
        flat = yaml_scalars(self.settings.read_text(encoding="utf-8"))
        out = {}
        for k, s in flat.items():
            if not k.startswith("patch/"):
                continue
            path = k[len("patch/"):]
            f = FIELD_BY_PATH.get(path)
            if f is None:
                continue
            v = parse_value(f, s)
            if v is not None:
                out[path] = v
        return out

    def write_overrides(self, values):
        lines = [
            "# 由 Suzu 设置页生成，请在设置页里修改。经 " + f"{self.schema}.custom.yaml 末尾的 __patch 引用，优先于其中的同名设置。",
            "patch:",
        ]
        for f in FIELDS:
            if f["path"] in values:
                lines.append(f'  "{f["path"]}": {fmt_value(values[f["path"]])}')
        write_atomic(self.settings, "\n".join(lines) + "\n")

    def effective(self):
        if not self.built_schema.exists():
            return {}
        flat = yaml_scalars(self.built_schema.read_text(encoding="utf-8"))
        out = {}
        for f in FIELDS:
            v = parse_value(f, flat.get(f["path"]))
            if v is not None:
                out[f["path"]] = v
        return out

    # --- 候选映射
    def emoji_entries(self):
        p = self.root / EMOJI_FILE
        if not p.exists():
            return []
        out = []
        for line in p.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t", 1)
            if len(parts) == 2 and parts[0].strip() and parts[1].strip():
                out.append({"key": parts[0].strip(), "emoji": parts[1].strip()})
        return out

    def write_emoji(self, entries):
        clean = []
        for e in entries:
            k = normalize_key(str(e.get("key", "")))
            v = normalize_emoji(str(e.get("emoji", "")))
            if k is None or v is None:
                raise ValueError("每一行都要有键和候选，且不能含 Tab 或换行")
            clean.append((k, v))
        write_atomic(self.root / EMOJI_FILE, EMOJI_HEADER + "".join(f"{k}\t{v}\n" for k, v in clean))
        return len(clean)

    # --- 状态
    def status(self):
        lock = {}
        lp = self.root / "dict_pack.lock"
        if lp.exists():
            for line in lp.read_text(encoding="utf-8").splitlines():
                if "\t" in line and not line.startswith("#"):
                    k, v = line.split("\t", 1)
                    lock[k.strip()] = v.strip()
        model = self.root / "suzu.gguf"
        core = self.root / "lua" / ("rime_llm.dll" if os.name == "nt" else "rime_llm.so")
        return {
            "rime_dir": str(self.root),
            "schema": self.schema,
            "frontend": frontend_name(),
            "deploy_available": deploy_command() is not None,
            "hook": self.hook_state(),
            "pack": lock.get("name") or lock.get("pack"),
            "pack_commit": (lock.get("commit") or "")[:12],
            "model": model.exists(),
            "model_mb": round(model.stat().st_size / 1e6, 1) if model.exists() else None,
            "core": core.exists(),
            "built_at": int(self.built_schema.stat().st_mtime) if self.built_schema.exists() else None,
        }


def normalize_key(raw):
    """与安卓设置页一致：纯字母（可带隔音符、空格）转成小写拼音，其余去掉首尾空白；不合法返回 None。"""
    s = raw.strip()
    if not s or "\t" in s or "\n" in s:
        return None
    letters = s.replace("'", "").replace(" ", "")
    if letters and all("a" <= c <= "z" or "A" <= c <= "Z" for c in letters):
        return letters.lower()
    return s


def normalize_emoji(raw):
    s = re.sub(r"\s+", " ", raw.strip())
    if not s or "\t" in s:
        return None
    return s


def write_atomic(path, text):
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


# ---------------------------------------------------------------- 词库包

def list_packs():
    tsv = REPO / "packs" / "packs.tsv"
    out = []
    if not tsv.exists():
        return out
    for line in tsv.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#") or line.startswith("name\t"):
            continue
        cols = line.split("\t")
        if len(cols) >= 6:
            out.append({"name": cols[0], "license": cols[3], "note": cols[5]})
    return out


def install_pack(rime, name):
    if name not in {p["name"] for p in list_packs()}:
        raise ValueError("没有这个词库包")
    r = subprocess.run([sys.executable, "-I", str(REPO / "tools" / "dict_pack.py"), "install", name,
                        "--rime-dir", str(rime.root), "--schema", rime.schema],
                       capture_output=True, text=True, timeout=900)
    tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-6:])
    if r.returncode != 0:
        raise RuntimeError(f"词库包安装失败：\n{tail}")
    return tail


# ---------------------------------------------------------------- 部署

DEPLOY_DONE = re.compile(r"deployer\.cc:\d+\] (\d+) tasks ran: (\d+) success, (\d+) failure")
SCHEMA_DONE = re.compile(r"finished updating schemas: (\d+) success, (\d+) failure")


def parse_deploy_log(lines):
    """从部署开始后新增的 INFO 日志里找结束标记。返回 None（未结束）或结果字典。"""
    schemas = None
    for l in lines:
        m = SCHEMA_DONE.search(l)
        if m:
            schemas = {"success": int(m.group(1)), "failure": int(m.group(2))}
        m = DEPLOY_DONE.search(l)
        if m:
            return {"tasks": int(m.group(1)), "success": int(m.group(2)), "failure": int(m.group(3)),
                    "schemas": schemas}
    return None


def read_new_lines(path, offset):
    try:
        with open(path, "rb") as fh:
            fh.seek(offset)
            data = fh.read()
        return data.decode("utf-8", "replace").splitlines()
    except OSError:
        return []


def file_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def deploy_and_wait(timeout=180):
    cmd = deploy_command()
    if cmd is None:
        raise RuntimeError("没有找到输入法的部署程序，请在输入法菜单里手动重新部署")
    name = frontend_name()
    info, warn = log_dir() / f"rime.{name}.INFO", log_dir() / f"rime.{name}.WARNING"
    info_off, warn_off = file_size(info), file_size(warn)
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    result = None
    while time.time() - t0 < timeout:
        time.sleep(0.5)
        # 日志文件可能在部署时轮换成新文件：变小了就从头读
        if file_size(info) < info_off:
            info_off = 0
        result = parse_deploy_log(read_new_lines(info, info_off))
        if result:
            break
    if file_size(warn) < warn_off:
        warn_off = 0
    warnings = [l for l in read_new_lines(warn, warn_off) if l[:1] in ("W", "E", "F")]
    errors = [l for l in warnings if l[:1] in ("E", "F")]
    dup = sum(1 for l in warnings if "duplicate word definition" in l)
    other = [l for l in warnings if "duplicate word definition" not in l]
    return {
        "finished": result is not None,
        "seconds": round(time.time() - t0, 1),
        "result": result,
        "errors": len(errors),
        "duplicate_words": dup,
        "messages": [l[:300] for l in other[-20:]],
    }


# ---------------------------------------------------------------- HTTP

class App:
    def __init__(self, rime, port):
        self.rime = rime
        self.port = port
        self.token = secrets.token_urlsafe(24)
        self.lock = threading.Lock()   # 部署与词库安装不并发
        self.last_seen = time.time()   # 最近一次请求的时间，供闲置退出使用

    def state(self):
        return {
            "status": self.rime.status(),
            "fields": FIELDS,
            "effective": self.rime.effective(),
            "overrides": self.rime.overrides(),
            "emoji": self.rime.emoji_entries(),
            "packs": list_packs(),
        }

    def handle(self, method, path, body):
        if method == "GET" and path == "/api/state":
            return self.state()
        if method != "POST":
            raise LookupError(path)
        if path == "/api/settings":
            values = {}
            for p, v in (body.get("overrides") or {}).items():
                f = FIELD_BY_PATH.get(p)
                if f is None:
                    raise ValueError(f"未知设置：{p}")
                if v is not None:
                    values[p] = check_value(f, v)
            hook = self.rime.ensure_hook()
            self.rime.write_overrides(values)
            out = {"saved": len(values), "hook": hook}
            if body.get("deploy"):
                with self.lock:
                    out["deploy"] = deploy_and_wait()
            out["state"] = self.state()
            return out
        if path == "/api/emoji":
            n = self.rime.write_emoji(body.get("entries") or [])
            return {"saved": n, "state": self.state()}
        if path == "/api/deploy":
            with self.lock:
                return {"deploy": deploy_and_wait(), "state": self.state()}
        if path == "/api/pack":
            with self.lock:
                log = install_pack(self.rime, str(body.get("name", "")))
                dep = deploy_and_wait(timeout=600)
            return {"install": log, "deploy": dep, "state": self.state()}
        raise LookupError(path)


def make_handler(app):
    page = (HERE / "index.html").read_text(encoding="utf-8")
    allowed_hosts = {f"127.0.0.1:{app.port}", f"localhost:{app.port}"}

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "SuzuSettings"

        def log_message(self, fmt, *args):
            pass

        def _send(self, code, data, ctype="application/json; charset=utf-8"):
            raw = data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(raw)

        def _guard(self, write):
            if self.headers.get("Host", "") not in allowed_hosts:
                self._send(403, {"error": "Host 不符"})
                return False
            if write and self.headers.get("X-Suzu-Token", "") != app.token:
                self._send(403, {"error": "令牌不符，请刷新页面"})
                return False
            return True

        def _dispatch(self, method):
            app.last_seen = time.time()
            path = self.path.split("?", 1)[0]
            if method == "GET" and path in ("/", "/index.html"):
                if self._guard(False):
                    html = page.replace("__SUZU_TOKEN__", app.token)
                    self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
                return
            if not self._guard(method == "POST"):
                return
            body = {}
            if method == "POST":
                n = int(self.headers.get("Content-Length") or 0)
                if n > 1_000_000:
                    self._send(413, {"error": "请求过大"})
                    return
                try:
                    body = json.loads(self.rfile.read(n) or b"{}")
                except json.JSONDecodeError:
                    self._send(400, {"error": "请求不是 JSON"})
                    return
            try:
                self._send(200, app.handle(method, path, body))
            except LookupError:
                self._send(404, {"error": "没有这个地址"})
            except (ValueError, RuntimeError) as e:
                self._send(400, {"error": str(e)})
            except Exception as e:   # 兜底：返回错误而不是断开连接
                self._send(500, {"error": f"{type(e).__name__}: {e}"})

        def do_GET(self):
            self._dispatch("GET")

        def do_POST(self):
            self._dispatch("POST")

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description="Suzu 设置页")
    ap.add_argument("--rime-dir", default=str(default_rime_dir()))
    ap.add_argument("--schema", default="rime_ice")
    ap.add_argument("--port", type=int, default=8767)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--idle-exit", type=float, default=0, metavar="分钟",
                    help="闲置这么多分钟（没有任何请求、也没在部署）后自动退出，0 为不退出")
    a = ap.parse_args(argv)
    root = Path(a.rime_dir).expanduser()
    if not root.is_dir():
        sys.exit(f"Rime 用户目录不存在：{root}")
    app = App(RimeDir(root, a.schema), a.port)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(app))
    url = f"http://127.0.0.1:{a.port}/"
    print(f"Suzu 设置页：{url}（Ctrl+C 退出）", flush=True)
    if not a.no_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    if a.idle_exit > 0:
        def watchdog():
            while True:
                time.sleep(min(30, a.idle_exit * 60 / 4))
                if time.time() - app.last_seen > a.idle_exit * 60 and not app.lock.locked():
                    print("闲置超时，退出", flush=True)
                    srv.shutdown()
                    return
        threading.Thread(target=watchdog, daemon=True).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
