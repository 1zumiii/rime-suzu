#!/usr/bin/env python3
"""suzu_settings.py 的自测：只用编造的配置与临时目录。用法：python3 -I tools/settings/test_suzu_settings.py"""
import http.client
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import suzu_settings as ss  # noqa: E402

CUSTOM = """patch:
  "engine/filters/@before 4": lua_filter@*recent_boost_filter
  recent_boost_filter:
    idx: 2             # 提升到第几个候选位置
    window_hours: 72
  llm_rerank:
    max_candidates: 10   # 注释里有冒号: 不影响
    unified:
      alpha: 0.05
      top_gate: 2.5
"""

BUILT = """__build_info:
  rime_version: 1.16.0
llm_rerank:
  badge: "◇"
  max_candidates: 10
  stage2: true
  unified:
    alpha: 0.05
    top_gate: 2.5
recent_boost_filter:
  idx: 2
  window_hours: 72
switches:
  - name: ascii_mode
    states: [中, Ａ]
"""


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.rime = ss.RimeDir(self.root, "rime_ice")

    def tearDown(self):
        self.tmp.cleanup()


class YamlTest(unittest.TestCase):
    def test_scalars(self):
        d = ss.yaml_scalars(BUILT)
        self.assertEqual(d["llm_rerank/unified/top_gate"], "2.5")
        self.assertEqual(d["llm_rerank/badge"], "◇")
        self.assertEqual(d["recent_boost_filter/idx"], "2")
        self.assertNotIn("switches/name", d)

    def test_quoted_keys_and_comments(self):
        d = ss.yaml_scalars('patch:\n  "llm_rerank/unified/top_gate": 3.0  # x\n  "a/b": "#不是注释"\n')
        self.assertEqual(d["patch/llm_rerank/unified/top_gate"], "3.0")
        self.assertEqual(d["patch/a/b"], "#不是注释")


class HookTest(Base):
    def test_add_hook_keeps_original(self):
        self.rime.custom.write_text(CUSTOM, encoding="utf-8")
        self.assertEqual(self.rime.hook_state(), "missing")
        self.assertEqual(self.rime.ensure_hook(), "added")
        text = self.rime.custom.read_text(encoding="utf-8")
        self.assertTrue(text.startswith(CUSTOM))
        self.assertIn("\n  " + ss.HOOK + "\n", text)
        self.assertEqual(self.rime.hook_state(), "ok")
        self.assertEqual(self.rime.ensure_hook(), "ok")
        self.assertEqual(text.count(ss.HOOK), 1)
        bak = self.root / "rime_ice.custom.yaml.bak-before-settings"
        self.assertEqual(bak.read_text(encoding="utf-8"), CUSTOM)

    def test_create_when_missing(self):
        self.assertEqual(self.rime.ensure_hook(), "created")
        self.assertEqual(self.rime.hook_state(), "ok")

    def test_four_space_indent(self):
        self.rime.custom.write_text("patch:\n    a/b: 1\n", encoding="utf-8")
        self.rime.ensure_hook()
        self.assertIn("\n    " + ss.HOOK + "\n", self.rime.custom.read_text(encoding="utf-8"))

    def test_manual_when_patch_not_last(self):
        self.rime.custom.write_text("patch:\n  a: 1\nother:\n  b: 2\n", encoding="utf-8")
        self.assertEqual(self.rime.hook_state(), "manual")
        with self.assertRaises(RuntimeError):
            self.rime.ensure_hook()

    def test_manual_when_other_patch_directive(self):
        self.rime.custom.write_text("patch:\n  __patch: other:/patch\n", encoding="utf-8")
        self.assertEqual(self.rime.hook_state(), "manual")


class OverrideTest(Base):
    def test_roundtrip(self):
        vals = {"llm_rerank/unified/top_gate": 3.7, "llm_rerank/stage2": False, "recent_boost_filter/idx": 3}
        self.rime.write_overrides(vals)
        self.assertEqual(self.rime.overrides(), vals)

    def test_unknown_keys_ignored(self):
        self.rime.settings.write_text('patch:\n  "x/y": 1\n  "recent_boost_filter/idx": 4\n', encoding="utf-8")
        self.assertEqual(self.rime.overrides(), {"recent_boost_filter/idx": 4})

    def test_effective(self):
        (self.root / "build").mkdir()
        self.rime.built_schema.write_text(BUILT, encoding="utf-8")
        eff = self.rime.effective()
        self.assertEqual(eff["llm_rerank/unified/top_gate"], 2.5)
        self.assertIs(eff["llm_rerank/stage2"], True)
        self.assertEqual(eff["recent_boost_filter/window_hours"], 72)
        self.assertNotIn("llm_rerank/pair_gamma", eff)

    def test_check_value(self):
        f = ss.FIELD_BY_PATH
        self.assertEqual(ss.check_value(f["recent_boost_filter/idx"], 3.0), 3)
        for bad in (0, 10, 2.5, "3", True):
            with self.assertRaises(ValueError):
                ss.check_value(f["recent_boost_filter/idx"], bad)
        with self.assertRaises(ValueError):
            ss.check_value(f["llm_rerank/stage2"], 1)
        self.assertEqual(ss.check_value(f["llm_rerank/unified/alpha"], 0), 0.0)


class EmojiTest(Base):
    def test_roundtrip_and_normalize(self):
        n = self.rime.write_emoji([{"key": " Shang ", "emoji": "☝️"}, {"key": "尴尬", "emoji": " 😅   🙃 "},
                                   {"key": "xi'an", "emoji": "🏯"}])
        self.assertEqual(n, 3)
        text = (self.root / ss.EMOJI_FILE).read_text(encoding="utf-8")
        self.assertTrue(text.startswith("#"))
        self.assertIn("shang\t☝️\n", text)
        self.assertIn("尴尬\t😅 🙃\n", text)
        self.assertIn("xian\t🏯\n", text)
        self.assertEqual(self.rime.emoji_entries()[1], {"key": "尴尬", "emoji": "😅 🙃"})

    def test_reject_bad(self):
        for bad in ({"key": "", "emoji": "😅"}, {"key": "a", "emoji": " "}, {"key": "a\tb", "emoji": "😅"}):
            with self.assertRaises(ValueError):
                self.rime.write_emoji([bad])


class DeployLogTest(unittest.TestCase):
    def test_parse(self):
        lines = [
            "I20261117 22:46:07.575414 0x1 deployer.cc:119] starting work thread for 3 tasks.",
            "I20261117 22:46:07.989578 0x1 deployment_tasks.cc:247] finished updating schemas: 3 success, 0 failure.",
            "I20261117 22:46:07.991238 0x1 deployer.cc:97] 3 tasks ran: 3 success, 0 failure.",
        ]
        self.assertIsNone(ss.parse_deploy_log(lines[:2]))
        r = ss.parse_deploy_log(lines)
        self.assertEqual(r["failure"], 0)
        self.assertEqual(r["schemas"], {"success": 3, "failure": 0})


class HttpTest(Base):
    def setUp(self):
        super().setUp()
        self.rime.custom.write_text(CUSTOM, encoding="utf-8")
        app = ss.App(self.rime, 0)
        srv = ss.http.server.ThreadingHTTPServer(("127.0.0.1", 0), None)
        app.port = srv.server_address[1]
        srv.RequestHandlerClass = ss.make_handler(app)
        self.app, self.srv = app, srv
        threading.Thread(target=srv.serve_forever, daemon=True).start()

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        super().tearDown()

    def req(self, method, path, body=None, host=None, token=None):
        c = http.client.HTTPConnection("127.0.0.1", self.app.port, timeout=5)
        h = {"Host": host or f"127.0.0.1:{self.app.port}", "Content-Type": "application/json"}
        if token:
            h["X-Suzu-Token"] = token
        c.request(method, path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        data = r.read()
        c.close()
        return r.status, data

    def test_page_has_token(self):
        st, data = self.req("GET", "/")
        self.assertEqual(st, 200)
        self.assertIn(self.app.token.encode(), data)

    def test_host_guard(self):
        st, _ = self.req("GET", "/api/state", host="evil.example:80")
        self.assertEqual(st, 403)

    def test_token_guard(self):
        st, _ = self.req("POST", "/api/settings", {"overrides": {}})
        self.assertEqual(st, 403)
        self.assertFalse(self.rime.settings.exists())

    def test_save_settings(self):
        st, data = self.req("POST", "/api/settings", {"overrides": {"llm_rerank/unified/top_gate": 3}}, token=self.app.token)
        self.assertEqual(st, 200, data)
        out = json.loads(data)
        self.assertEqual(out["hook"], "added")
        self.assertEqual(self.rime.overrides(), {"llm_rerank/unified/top_gate": 3.0})

    def test_reject_out_of_range(self):
        st, data = self.req("POST", "/api/settings", {"overrides": {"recent_boost_filter/idx": 99}}, token=self.app.token)
        self.assertEqual(st, 400)
        self.assertFalse(self.rime.settings.exists())

    def test_state(self):
        st, data = self.req("GET", "/api/state")
        self.assertEqual(st, 200)
        s = json.loads(data)
        self.assertEqual(s["status"]["hook"], "missing")
        self.assertTrue(any(p["name"] == "frost" for p in s["packs"]))


if __name__ == "__main__":
    unittest.main(verbosity=1)
