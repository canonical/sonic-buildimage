# 在 Testflinger 上自动跑 sonic-mgmt t0 —— 实施计划

> **致 agent 执行者：** 必需的子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐个任务实施本计划。各步骤用复选框（`- [ ]`）语法跟踪进度。

**目标：** 在 `canonical/sonic-buildimage` 中加一个 GitHub Actions workflow：在一台 Testflinger 机器上，对 `resolute-build` 产出的 vs 镜像跑上游 sonic-mgmt t0 checker 列表，对照仓库里的已知失败清单判定结果，并在每晚、push/tag 构建之后以及 PR 评论 `/test-t0` 时汇报。

**架构：** 一个 workflow（`resolute-t0.yml`），包含在 `ubuntu-latest` 上运行的短 job `resolve`，以及在 small 自建 runner 上运行的长 job `t0`。`t0` job 把镜像发布为 release 附件，用官方 submit action（`poll: true`，`retries: 2`）提交 Testflinger job，再用 `verdict.py` 判定取回的 artifacts。在 Testflinger 机器上，`run-t0.sh` 创建 LXD 虚拟机，每个虚拟机（`tb-run.sh`）搭一个 `vms-kvm-t0` 测试床，从共享队列领取测试文件块，结果压缩后传回。设计文档：`202605_resolute_doc` 分支上的 `docs/superpowers/specs/2026-11-20-resolute-t0-testflinger-ci-design-en.md`。

以英文版（`-en.md`）为准；本中文版是翻译。

**技术栈：** GitHub Actions；Testflinger（`canonical/testflinger` 的 submit action、`testflinger-cli`）；bash；Python 3.12+，只用标准库和 PyYAML；pytest；Ubuntu 26.04 上的 LXD 虚拟机；sonic-mgmt 的 `run_tests.sh` / `testbed-cli.sh`；docker；zstd。

## 全局约束

- 在 worktree `~/scratch/wt-t0` 的 `feat/resolute-t0-testflinger` 分支上工作，该分支从 `canonical/202605_resolute` 创建。每条 git 命令都用 `git -C <dir>`：shell 的工作目录可能被静默重置到文档仓库。
- `202605_resolute` 是生产分支：改动只能经 pull request 进入。取消正在运行的 GitHub Actions run 之前，必须先问用户（AGENTS.md）。
- commit 用 GPG 签名（`commit.gpgsign` 已是 `true`），使用 `test:` 前缀，并以 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` 结尾。
- 代码注释：只在原因不明显的地方写，每条一行。根因和数字写进 commit message。
- Python 必须能在 Python 3.12（runner）和 3.14（Ubuntu 26.04）上运行，只用标准库加 PyYAML。
- `known-failures.yaml` 中每条 `reason` 都用英文写。
- 用户持有的 Testflinger 预留，没有用户明确发话，绝不释放或取消。
- 固定名称，各处一律原样使用：
  - Testflinger 队列 `sonic-ci-large`；Testflinger secret 路径 `sonic-buildimage/ghcr-read-token`
  - cEOS 镜像 `ghcr.io/canonical/sonic-ceos:4.32.5M-1`，在测试机上重新打标签为 `ceosimage:4.32.5M-1`
  - release tag `t0-images`；附件名 `sonic-vs-<sha12>.img.gz` 加 `.sha256`；保留最新的 10 个
  - commit 状态 context `resolute-t0`；PR 评论标记 `<!-- resolute-t0 -->`
  - runner 标签 `self-hosted-linux-amd64-noble-private-endpoint-small`；job `timeout-minutes: 1440`
  - submit action `canonical/testflinger/.github/actions/submit@257ef71c8042a41925d7185d46fc3171ea2112f5`（submit/v1.6.0）
  - 定时 `cron: "0 15 * * *"`；job 文件 `global_timeout: 43200`、`output_timeout: 7200`
  - sonic-mgmt 锁定版本 `a88d1d5f9323833d8cf2e050c84904deb22ed3bc`（`canonical/sonic-mgmt`）
  - 测试床 `vms-kvm-t0`，DUT `vlab-01`，虚拟机用户 `tb`；块的目标时长 3000 秒，没有记录的文件按 480 秒估算
  - 定规模 T = min(⌊(内存 GiB − 16) / 18⌋, ⌊线程数 / 8⌋, ⌊存储池可用 GB / 40⌋)，冒烟时最多为 2；测试脚本启动 37800 秒后停止派发，41400 秒时强制停止

---

## 文件结构

全部是新文件，位于 `canonical/sonic-buildimage`：

| 文件 | 职责 |
|---|---|
| `.github/workflows/resolute-t0.yml` | 触发、确定要测的构建、发布镜像、提交 Testflinger job、判定、汇报 |
| `.github/testflinger/t0/make_chunks.py` | 按预计耗时把测试文件打包成块 |
| `.github/testflinger/t0/verdict.py` | 解析 JUnit、挑出要重跑的文件、对照已知清单给用例归类、写出 summary/report/durations |
| `.github/testflinger/t0/configure_sonic_mgmt.py` | 把 KVM 测试床配置应用到 sonic-mgmt 目录树 |
| `.github/testflinger/t0/render_job.py` + `job.yaml.in` | 渲染 Testflinger job 文件 |
| `.github/testflinger/t0/agent.sh` | agent 端：复制测试脚本、以脱离会话的方式启动、转发进度、取回 artifacts |
| `.github/testflinger/t0/run-t0.sh` | 测试机入口：阶段划分、启动虚拟机、监控、时间保护、打包、`run-meta.json` |
| `.github/testflinger/t0/host-setup.sh` | 宿主机软件包、LXD、存储池、swap、防火墙、共享镜像、定规模 |
| `.github/testflinger/t0/tb-run.sh` | 一个虚拟机里的一个测试床：工具、add-topo、deploy-mg、领块循环、重跑 |
| `.github/testflinger/t0/known-failures.yaml` | 经过审查的已知失败和 loganalyzer 噪声规则 |
| `.github/testflinger/t0/sonic-mgmt.ref` | 锁定的 sonic-mgmt commit |
| `.github/testflinger/t0/smoke.txt` | 冒烟测试列表 |
| `.github/testflinger/t0/tests/` | pytest 测试：`conftest.py`、`test_make_chunks.py`、`test_verdict.py`、`test_configure_sonic_mgmt.py`、`test_render_job.py`、`test_shell_syntax.py` |

测试命令（在 worktree 根目录执行）：`python3 -m pytest -q .github/testflinger/t0/tests`

---

### 任务 1：worktree 和分块打包

**文件：**
- 新建：`.github/testflinger/t0/make_chunks.py`
- 新建：`.github/testflinger/t0/tests/conftest.py`
- 测试：`.github/testflinger/t0/tests/test_make_chunks.py`

**接口：**
- 产出：`make_chunks.pack(files: list[str], durations: dict[str, float], target: float = 3000.0, default: float = 480.0) -> list[list[str]]`；CLI `make_chunks.py <file list> <durations.json> <out dir> [target] [default]`，写出文件 `000`、`001`、…（每行一个测试文件）。

- [ ] **第 1 步：创建 worktree**

```bash
R=/home/sheldon-qi/sonic-buildimage-resolute
git -C $R fetch -q canonical 202605_resolute
git -C $R worktree add -q --no-checkout -b feat/resolute-t0-testflinger ~/scratch/wt-t0 canonical/202605_resolute
git -C ~/scratch/wt-t0 sparse-checkout set --no-cone /.github/ /AGENTS.md
git -C ~/scratch/wt-t0 checkout -q
git -C ~/scratch/wt-t0 branch --show-current
```

预期：`feat/resolute-t0-testflinger`。

- [ ] **第 2 步：编写会失败的测试**

`.github/testflinger/t0/tests/conftest.py`：

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

`.github/testflinger/t0/tests/test_make_chunks.py`：

```python
import json
import subprocess
import sys
from pathlib import Path

import make_chunks


def test_every_file_appears_once():
    chunks = make_chunks.pack(["a.py", "b.py", "c.py", "a.py"], {"a.py": 100, "b.py": 200}, target=300, default=50)
    assert sorted(f for chunk in chunks for f in chunk) == ["a.py", "b.py", "c.py"]


def test_chunks_stay_under_target_unless_one_file_is_longer():
    durations = {"long.py": 5000, "x.py": 1000, "y.py": 1500, "z.py": 900}
    chunks = make_chunks.pack(list(durations), durations, target=3000)
    for chunk in chunks:
        assert sum(durations[f] for f in chunk) <= 3000 or len(chunk) == 1
    assert ["long.py"] in chunks


def test_longest_chunk_first_and_default_for_unknown_files():
    chunks = make_chunks.pack(["new.py", "short.py"], {"short.py": 10}, target=100, default=480)
    assert chunks[0] == ["new.py"]


def test_target_one_puts_every_file_in_its_own_chunk():
    assert sorted(make_chunks.pack(["a.py", "b.py", "c.py"], {}, target=1)) == [["a.py"], ["b.py"], ["c.py"]]


def test_cli_writes_numbered_chunk_files(tmp_path):
    (tmp_path / "files.txt").write_text("a.py\nb.py\n")
    (tmp_path / "d.json").write_text(json.dumps({"a.py": 2000, "b.py": 2000}))
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "d.json"), str(tmp_path / "out"), "3000"], check=True)
    names = sorted(p.name for p in (tmp_path / "out").iterdir())
    assert names == ["000", "001"]
    assert {(tmp_path / "out" / n).read_text().strip() for n in names} == {"a.py", "b.py"}


def test_cli_without_durations_file(tmp_path):
    (tmp_path / "files.txt").write_text("a.py\n")
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "missing.json"), str(tmp_path / "out")], check=True)
    assert (tmp_path / "out" / "000").read_text() == "a.py\n"
```

- [ ] **第 3 步：运行测试，确认失败**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
预期：FAIL，报 `ModuleNotFoundError: No module named 'make_chunks'`。

- [ ] **第 4 步：编写 `make_chunks.py`**

```python
#!/usr/bin/env python3
"""Pack test files into chunks of about TARGET seconds, longest first.

usage: make_chunks.py <file list> <durations.json> <out dir> [target seconds] [default seconds]
"""
import json
import os
import sys


def pack(files, durations, target=3000.0, default=480.0):
    est = {f: float(durations.get(f, default)) for f in files}
    chunks = []
    for f in sorted(dict.fromkeys(files), key=lambda f: (-est[f], f)):
        best = None
        for chunk in chunks:
            if chunk["t"] + est[f] <= target and (best is None or chunk["t"] > best["t"]):
                best = chunk
        if best is None:
            best = {"t": 0.0, "files": []}
            chunks.append(best)
        best["files"].append(f)
        best["t"] += est[f]
    chunks.sort(key=lambda c: -c["t"])
    return [c["files"] for c in chunks]


def main(argv):
    with open(argv[1]) as fh:
        files = [line.strip() for line in fh if line.strip()]
    durations = {}
    if os.path.exists(argv[2]):
        with open(argv[2]) as fh:
            durations = json.load(fh)
    target = float(argv[4]) if len(argv) > 4 else 3000.0
    default = float(argv[5]) if len(argv) > 5 else 480.0
    chunks = pack(files, durations, target, default)
    os.makedirs(argv[3], exist_ok=True)
    for i, chunk in enumerate(chunks):
        with open(os.path.join(argv[3], "%03d" % i), "w") as fh:
            fh.write("\n".join(chunk) + "\n")
    print("%d files -> %d chunks" % (len(set(files)), len(chunks)))


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **第 5 步：运行测试，确认通过**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
预期：`6 passed`。

- [ ] **第 6 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/make_chunks.py .github/testflinger/t0/tests/conftest.py .github/testflinger/t0/tests/test_make_chunks.py
git -C $W commit -m "test: pack sonic-mgmt test files into chunks by expected duration

Longest file first into the fullest chunk that still fits, so testbeds
finish at about the same time; files with no recorded duration count
480 s, as in the 2026-11-19 farm run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 2：判定 —— JUnit 解析和已知失败匹配

**文件：**
- 新建：`.github/testflinger/t0/verdict.py`
- 测试：`.github/testflinger/t0/tests/test_verdict.py`

**接口：**
- 产出：`Case(outcome: str, message: str = "")`，outcome 取值为 `passed|skipped|failed|error`；`id_pattern(text) -> re.Pattern`；`Known(path)`，带 `.entries`（含 `id`、`kind`、`reason`、`_re`、`_file` 的 dict）、`.noise`（编译好的正则）、`.covers(cid, case) -> bool`；`case_id(rel_xml, classname, name) -> str`；`parse_xml(path, rel_xml, noise) -> dict[str, Case]`；`chunk_dirs(results) -> iterator of ((chunk, retry, rerun), Path)`；`parse_dir(d, noise) -> dict[test file, dict[str, Case]]`；`load_results(results, noise) -> (first: dict[str, Case], final: dict[str, Case], ran: set[str])`；常量 `SKIP_XML`、`CHUNK_DIR`、`BAD`。

- [ ] **第 1 步：编写会失败的测试**

`.github/testflinger/t0/tests/test_verdict.py`：

```python
import json
import re
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

import pytest
import yaml

import verdict

NOISE = r"nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)"
LA = ('failed on teardown with "Failed: Got matched syslog in processes "analyze_logs--<MultiAsicSonicHost vlab-01>" '
      'exit code:"1"\nmatch: 1\n\nMatch Messages:\n2026 Nov 19 11:59:45.003096 vlab-01 ERR {}\n')
TACPLUS = LA.format("unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed")
OTHER = LA.format("orchagent: :- doTask: something broke")
SCRIPT = Path(verdict.__file__)


def fail(msg):
    return "<failure message=%s/>" % quoteattr(msg)


def err(msg):
    return "<error message=%s/>" % quoteattr(msg)


def skip(msg="skipped"):
    return "<skipped message=%s/>" % quoteattr(msg)


def junit(path, cases, suite_time=1.0):
    body = "".join('<testcase classname="%s" name="%s" time="1">%s</testcase>' % c for c in cases)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('<?xml version="1.0"?><testsuites name="pytest tests"><testsuite name="pytest" time="%s">%s'
                    '</testsuite></testsuites>' % (suite_time, body))


def known_file(tmp_path, entries=()):
    path = tmp_path / "known.yaml"
    path.write_text(yaml.safe_dump({"known": list(entries),
                                    "loganalyzer_noise": [{"pattern": NOISE, "reason": "noise"}]}))
    return path


def test_case_id_for_function_and_class():
    assert verdict.case_id("test_interfaces.xml", "tests.test_interfaces", "test_interfaces[vlab-01-None]") == \
        "test_interfaces.py::test_interfaces[vlab-01-None]"
    assert verdict.case_id("acl/test_acl.xml", "tests.acl.test_acl.TestBasicAcl", "test_rule[ipv4]") == \
        "acl/test_acl.py::TestBasicAcl::test_rule[ipv4]"


def test_id_pattern_star_and_brackets():
    exact = verdict.id_pattern("snmp/test_x.py::test_a[vlab-01]")
    assert exact.match("snmp/test_x.py::test_a[vlab-01]")
    assert not exact.match("snmp/test_x.py::test_a[vlab-02]")
    assert verdict.id_pattern("generic_hash/*").match("generic_hash/test_g.py::test_h[ipv4-1]")


def test_outcomes_and_first_message_line(tmp_path):
    xml = tmp_path / "snmp" / "test_x.xml"
    junit(xml, [("tests.snmp.test_x", "test_pass", ""),
                ("tests.snmp.test_x", "test_fail", fail("assert 1 == 2\nmore detail")),
                ("tests.snmp.test_x", "test_setup", err('failed on setup with "boom"')),
                ("tests.snmp.test_x", "test_skip", skip())])
    cases = verdict.parse_xml(xml, "snmp/test_x.xml", [])
    assert {cid: c.outcome for cid, c in cases.items()} == {
        "snmp/test_x.py::test_pass": "passed", "snmp/test_x.py::test_fail": "failed",
        "snmp/test_x.py::test_setup": "error", "snmp/test_x.py::test_skip": "skipped"}
    assert cases["snmp/test_x.py::test_fail"].message == "assert 1 == 2"


def test_loganalyzer_noise_only_is_ignored(tmp_path):
    xml = tmp_path / "t.xml"
    junit(xml, [("tests.t", "a", ""), ("tests.t", "a", err(TACPLUS)),
                ("tests.t", "b", ""), ("tests.t", "b", err(OTHER)),
                ("tests.t", "c", err('failed on teardown with "fixture exploded"'))])
    cases = verdict.parse_xml(xml, "t.xml", [re.compile(NOISE)])
    assert cases["t.py::a"].outcome == "passed"
    assert cases["t.py::b"].outcome == "error"
    assert "doTask" in cases["t.py::b"].message
    assert cases["t.py::c"].outcome == "error"


def test_known_rejects_entry_without_reason(tmp_path):
    with pytest.raises(ValueError):
        verdict.Known(known_file(tmp_path, [{"id": "a.py::x", "kind": "fail"}]))


def test_known_covers_by_kind(tmp_path):
    known = verdict.Known(known_file(tmp_path, [{"id": "a.py::x", "kind": "fail", "reason": "r"},
                                                {"id": "a.py::f*", "kind": "flaky", "reason": "r"}]))
    assert known.covers("a.py::x", verdict.Case("failed"))
    assert not known.covers("a.py::x", verdict.Case("error"))
    assert known.covers("a.py::flaky_one", verdict.Case("error"))


def test_load_results_prefers_the_last_attempt(tmp_path):
    junit(tmp_path / "r" / "tb1" / "000" / "a.xml", [("tests.a", "x", fail("first")), ("tests.a", "y", "")])
    junit(tmp_path / "r" / "tb1" / "000.rerun" / "a.xml", [("tests.a", "x", "")])
    junit(tmp_path / "r" / "tb2" / "001" / "b.xml", [("tests.b", "z", skip())])
    junit(tmp_path / "r" / "tb2" / "001" / "pretest.xml", [("tests.test_pretest", "p", fail("ignored"))])
    first, final, ran = verdict.load_results(tmp_path / "r", [])
    assert first["a.py::x"].outcome == "failed" and final["a.py::x"].outcome == "passed"
    assert final["a.py::y"].outcome == "passed"
    assert ran == {"a.py", "b.py"}


def test_unreadable_junit_is_an_error(tmp_path):
    bad = tmp_path / "d" / "a.xml"
    bad.parent.mkdir(parents=True)
    bad.write_text("<testsuites><testsuite>")
    files = verdict.parse_dir(tmp_path / "d", [])
    assert [c.outcome for c in files["a.py"].values()] == ["error"]
```

- [ ] **第 2 步：运行测试，确认失败**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
预期：FAIL，报 `ModuleNotFoundError: No module named 'verdict'`。

- [ ] **第 3 步：编写 `verdict.py` 的第一部分**

```python
#!/usr/bin/env python3
"""Judge a resolute t0 run against known-failures.yaml.

  verdict.py rerun-files --chunk-dir DIR --known FILE
  verdict.py report --results DIR --known FILE --out-json F --out-md F --out-durations F [--meta F] [--infra REASON]

Result layout: DIR/<testbed>/<NNN[.retry][.rerun]>/<test file path>.xml, plus DIR/<testbed>/<NNN[.retry]>.time.
"""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import yaml

SKIP_XML = {"pretest.xml", "posttest.xml"}
CHUNK_DIR = re.compile(r"^(\d{3})(\.retry)?(\.rerun)?$")
SYSLOG_LINE = re.compile(r"\d{4} \w{3} +\d+ [\d:.]+ (\S+ [A-Z]+ [^\\\n'\"]*)")
BAD = ("failed", "error")


@dataclass
class Case:
    outcome: str
    message: str = ""


def id_pattern(text):
    return re.compile("^" + ".*".join(re.escape(part) for part in text.split("*")) + "$")


class Known:
    def __init__(self, path):
        data = yaml.safe_load(Path(path).read_text()) or {}
        self.entries = []
        for entry in data.get("known") or []:
            if entry.get("kind") not in ("fail", "error", "flaky") or not entry.get("id") or not entry.get("reason"):
                raise ValueError("bad known-failures entry: %r" % (entry,))
            self.entries.append(dict(entry, _re=id_pattern(entry["id"]),
                                     _file=id_pattern(entry["id"].split("::")[0])))
        self.noise = [re.compile(n["pattern"]) for n in data.get("loganalyzer_noise") or []]

    def covers(self, cid, case):
        want = "fail" if case.outcome == "failed" else "error"
        return any(e["kind"] in (want, "flaky") and e["_re"].match(cid) for e in self.entries)


def first_line(text):
    return (text.strip().splitlines() or [""])[0][:200]


def case_id(rel_xml, classname, name):
    module = rel_xml[:-len(".xml")]
    prefix = "tests." + module.replace("/", ".")
    rest = classname[len(prefix):] if classname == prefix or classname.startswith(prefix + ".") else classname
    return "::".join([module + ".py"] + [p for p in rest.split(".") if p] + [name])


def parse_xml(path, rel_xml, noise):
    grouped = {}
    for tc in ET.parse(path).iter("testcase"):
        grouped.setdefault(case_id(rel_xml, tc.get("classname", ""), tc.get("name", "")), []).append(tc)
    cases = {}
    for cid, elements in grouped.items():
        call, teardown, message = "passed", "ok", ""
        for tc in elements:
            for el in tc:
                msg = el.get("message") or ""
                text = msg + "\n" + (el.text or "")
                if el.tag == "error" and "on teardown" in msg:
                    lines = [m.strip() for m in SYSLOG_LINE.findall(text)] if "matched syslog" in text else []
                    residual = [line for line in lines if not any(n.search(line) for n in noise)]
                    if residual or not lines:
                        teardown = "error"
                        message = message or first_line(residual[0] if residual else (msg or text))
                elif el.tag == "error":
                    call, message = "error", first_line(msg or text)
                elif el.tag == "failure" and call != "error":
                    call, message = "failed", first_line(msg or text)
                elif el.tag == "skipped" and call == "passed":
                    call = "skipped"
        outcome = call if call in BAD else ("error" if teardown == "error" else call)
        cases[cid] = Case(outcome, message if outcome in BAD else "")
    return cases


def chunk_dirs(results):
    root = Path(results)
    if not root.is_dir():
        return
    for tb in sorted(p for p in root.iterdir() if p.is_dir()):
        for d in sorted(p for p in tb.iterdir() if p.is_dir()):
            m = CHUNK_DIR.match(d.name)
            if m:
                yield (m.group(1), bool(m.group(2)), bool(m.group(3))), d


def parse_dir(d, noise):
    files = {}
    for xml in sorted(Path(d).rglob("*.xml")):
        rel = xml.relative_to(d).as_posix()
        if rel in SKIP_XML:
            continue
        test_file = rel[:-len(".xml")] + ".py"
        try:
            files[test_file] = parse_xml(xml, rel, noise)
        except ET.ParseError as exc:
            files[test_file] = {test_file + "::<junit>": Case("error", "unreadable JUnit file: %s" % exc)}
    return files


def load_results(results, noise):
    attempts = {}
    for key, d in chunk_dirs(results):
        for test_file, cases in parse_dir(d, noise).items():
            attempts.setdefault(test_file, []).append((key, cases))
    first, final = {}, {}
    for runs in attempts.values():
        runs.sort(key=lambda run: run[0])
        for _, cases in runs:
            final.update(cases)
        for _, cases in reversed(runs):
            first.update(cases)
    return first, final, set(attempts)
```

- [ ] **第 4 步：运行测试，确认通过**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
预期：`8 passed`。

- [ ] **第 5 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/verdict.py .github/testflinger/t0/tests/test_verdict.py
git -C $W commit -m "test: parse sonic-mgmt JUnit results into pytest node ids

run_tests.sh -m individual writes one JUnit file per test file, so the
file path gives the module and the classname the class. Loganalyzer
teardown errors whose matched syslog lines are all known noise are
dropped: until PR #30 merges, nss_tacplus lines hit dozens of cases per
run (36 on 2026-11-19), on different cases each time.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 3：判定 —— 归类、报告和 CLI

**文件：**
- 修改：`.github/testflinger/t0/verdict.py`（追加）
- 测试：`.github/testflinger/t0/tests/test_verdict.py`（追加）

**接口：**
- 使用：任务 2 的全部产出。
- 产出：`classify(final, known, ran) -> (new: list[str], covered: list[str], now_passing: list[entry], stale: list[entry])`；`decide(new, not_run, infra) -> "infrastructure"|"regressions"|"incomplete"|"pass"`；`durations(results) -> dict[str, float]`；`render(summary) -> str`；CLI 子命令 `rerun-files`（每行打印一个测试文件）和 `report`（写出含 `outcome, state, title, description, infra, totals, new, covered, now_passing, stale, rerun_passed, not_run, meta, cases` 这些键的 `summary.json`、markdown 报告和 `durations.json`）。

- [ ] **第 1 步：把会失败的测试追加到 `test_verdict.py`**

```python
def test_decide_priority():
    assert verdict.decide(["x"], ["f.py"], "boom") == "infrastructure"
    assert verdict.decide(["x"], ["f.py"], "") == "regressions"
    assert verdict.decide([], ["f.py"], "") == "incomplete"
    assert verdict.decide([], [], "") == "pass"


def build_run(tmp_path):
    r = tmp_path / "results"
    junit(r / "tb1" / "000" / "a.xml", [("tests.a", "new", fail("boom")), ("tests.a", "known", fail("old bug")),
                                        ("tests.a", "flip", fail("flaky"))], suite_time=100)
    junit(r / "tb1" / "000.rerun" / "a.xml", [("tests.a", "new", fail("boom")), ("tests.a", "known", fail("old bug")),
                                              ("tests.a", "flip", "")])
    junit(r / "tb1" / "000" / "b.xml", [("tests.b", "fixed", "")], suite_time=50)
    (r / "tb1" / "000.time").write_text("0 450\n")
    meta = tmp_path / "run-meta.json"
    meta.write_text(json.dumps({"files": ["a.py", "b.py", "c.py"], "rc": 0, "phase": "done", "machine": "m1",
                                "testbeds": 2, "scope": "full", "image_sha256": "f" * 64,
                                "sonic_mgmt": "a88d1d5f93", "phases": {"tests": 3600}}))
    known = known_file(tmp_path, [
        {"id": "a.py::known", "kind": "fail", "reason": "old bug"},
        {"id": "b.py::fixed", "kind": "fail", "reason": "was broken"},
        {"id": "b.py::gone", "kind": "fail", "reason": "renamed since"},
        {"id": "z.py::*", "kind": "flaky", "reason": "not in this run"}])
    return r, meta, known


def report(tmp_path, *extra):
    out = tmp_path / "out"
    out.mkdir(exist_ok=True)
    subprocess.run([sys.executable, str(SCRIPT), "report", "--out-json", str(out / "summary.json"),
                    "--out-md", str(out / "report.md"), "--out-durations", str(out / "durations.json"), *extra],
                   check=True)
    return (json.loads((out / "summary.json").read_text()), (out / "report.md").read_text(),
            json.loads((out / "durations.json").read_text()))


def test_report_classifies_every_group(tmp_path):
    r, meta, known = build_run(tmp_path)
    summary, md, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert summary["outcome"] == "regressions" and summary["state"] == "failure"
    assert [c["id"] for c in summary["new"]] == ["a.py::new"]
    assert [c["id"] for c in summary["covered"]] == ["a.py::known"]
    assert summary["rerun_passed"] == ["a.py::flip"]
    assert [e["id"] for e in summary["now_passing"]] == ["b.py::fixed"]
    assert [e["id"] for e in summary["stale"]] == ["b.py::gone"]
    assert summary["not_run"] == ["c.py"]
    assert summary["totals"] == {"passed": 2, "skipped": 0, "failed": 2, "error": 0, "not_run_files": 1}
    assert "## resolute-t0: Regressions" in md and "`a.py::new`" in md


def test_report_without_meta_is_infrastructure(tmp_path):
    summary, _, _ = report(tmp_path, "--results", str(tmp_path / "none"), "--known", str(known_file(tmp_path)))
    assert summary["outcome"] == "infrastructure" and summary["state"] == "error"
    assert "no run-meta.json" in summary["description"]


def test_report_harness_failure_is_infrastructure(tmp_path):
    r, meta, known = build_run(tmp_path)
    data = json.loads(meta.read_text())
    data.update(rc=1, phase="payload")
    meta.write_text(json.dumps(data))
    summary, _, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert summary["outcome"] == "infrastructure" and "payload" in summary["infra"]


def test_report_infra_flag_wins(tmp_path):
    r, meta, known = build_run(tmp_path)
    summary, _, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta),
                           "--infra", "provisioning failed after the retries")
    assert summary["outcome"] == "infrastructure"
    assert summary["description"] == "Infrastructure: provisioning failed after the retries"


def test_durations_share_the_chunk_wall_time(tmp_path):
    r, meta, known = build_run(tmp_path)
    _, _, durations = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert durations == {"a.py": 250.0, "b.py": 200.0}


def test_rerun_files_lists_only_uncovered_failures(tmp_path):
    d = tmp_path / "000"
    junit(d / "a.xml", [("tests.a", "x", fail("new"))])
    junit(d / "b.xml", [("tests.b", "y", fail("known"))])
    junit(d / "c.xml", [("tests.c", "z", ""), ("tests.c", "z", err(TACPLUS))])
    junit(d / "pretest.xml", [("tests.test_pretest", "p", fail("ignored"))])
    known = known_file(tmp_path, [{"id": "b.py::y", "kind": "fail", "reason": "known"}])
    out = subprocess.run([sys.executable, str(SCRIPT), "rerun-files", "--chunk-dir", str(d), "--known", str(known)],
                         check=True, capture_output=True, text=True).stdout
    assert out.split() == ["a.py"]
```

- [ ] **第 2 步：运行测试，确认失败**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
预期：FAIL：`AttributeError: module 'verdict' has no attribute 'decide'`，CLI 测试因退出状态非零而失败。

- [ ] **第 3 步：把第二部分追加到 `verdict.py`**

```python
STATE = {"regressions": "failure", "incomplete": "error", "infrastructure": "error", "pass": "success"}
TITLE = {"regressions": "Regressions", "incomplete": "Incomplete", "infrastructure": "Infrastructure", "pass": "Pass"}
MAX_ROWS = 100


def classify(final, known, ran):
    new, covered = [], []
    for cid in sorted(final):
        case = final[cid]
        if case.outcome in BAD:
            (covered if known.covers(cid, case) else new).append(cid)
    now_passing, stale = [], []
    for entry in known.entries:
        hits = [cid for cid in final if entry["_re"].match(cid)]
        if not hits:
            if any(entry["_file"].match(f) for f in ran):
                stale.append(entry)
        elif entry["kind"] != "flaky" and all(final[c].outcome == "passed" for c in hits):
            now_passing.append(entry)
    return new, covered, now_passing, stale


def decide(new, not_run, infra):
    if infra:
        return "infrastructure"
    if new:
        return "regressions"
    if not_run:
        return "incomplete"
    return "pass"


def durations(results):
    out = {}
    for key, d in chunk_dirs(results):
        if key[2]:
            continue
        per = {}
        for xml in d.rglob("*.xml"):
            rel = xml.relative_to(d).as_posix()
            if rel in SKIP_XML:
                continue
            try:
                per[rel[:-len(".xml")] + ".py"] = sum(float(s.get("time", 0)) for s in ET.parse(xml).iter("testsuite"))
            except ET.ParseError:
                continue
        extra = 0.0
        timing = d.parent / (d.name + ".time")
        if per and timing.exists():
            start, end = (float(x) for x in timing.read_text().split()[:2])
            extra = max(0.0, (end - start) - sum(per.values())) / len(per)
        for test_file, seconds in per.items():
            out[test_file] = round(seconds + extra, 1)
    return out


def esc(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def table(rows, header):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(esc(c) for c in row) + " |" for row in rows[:MAX_ROWS]]
    if len(rows) > MAX_ROWS:
        lines += ["", "…and %d more in summary.json" % (len(rows) - MAX_ROWS)]
    return "\n".join(lines)


def bullets(items):
    lines = ["- " + item for item in items[:MAX_ROWS]]
    if len(items) > MAX_ROWS:
        lines.append("- …and %d more in summary.json" % (len(items) - MAX_ROWS))
    return lines


def render(summary):
    s, t, meta = summary, summary["totals"], summary["meta"]
    out = ["## resolute-t0: %s" % s["title"], ""]
    if s["infra"]:
        out += ["**Infrastructure problem:** %s" % s["infra"], ""]
    out += [table([[t["passed"], t["skipped"], t["failed"], t["error"], t["not_run_files"]]],
                  ["passed", "skipped", "failed", "errors", "files not run"]), ""]
    if s["new"]:
        out += ["### New failures (%d)" % len(s["new"]), "",
                table([["`%s`" % c["id"], c["outcome"], c["message"]] for c in s["new"]], ["case", "outcome", "message"]), ""]
    if s["rerun_passed"]:
        out += ["### Passed only on rerun (%d)" % len(s["rerun_passed"]), ""] + bullets(["`%s`" % c for c in s["rerun_passed"]]) + [""]
    if s["now_passing"]:
        out += ["### Known entries now passing (%d): remove them from known-failures.yaml" % len(s["now_passing"]), ""]
        out += bullets(["`%s` (%s): %s" % (e["id"], e["kind"], e["reason"]) for e in s["now_passing"]]) + [""]
    if s["stale"]:
        out += ["### Stale known entries (%d): they match no case in the files that ran" % len(s["stale"]), ""]
        out += bullets(["`%s` (%s): %s" % (e["id"], e["kind"], e["reason"]) for e in s["stale"]]) + [""]
    if s["not_run"]:
        out += ["### Files not run (%d)" % len(s["not_run"]), ""] + bullets(["`%s`" % f for f in s["not_run"]]) + [""]
    if s["covered"]:
        out += ["<details><summary>Known failures still failing (%d)</summary>" % len(s["covered"]), "",
                table([["`%s`" % c["id"], c["outcome"], c["message"]] for c in s["covered"]], ["case", "outcome", "message"]),
                "", "</details>", ""]
    phases = ", ".join("%s %dm" % (k, int(v) // 60) for k, v in (meta.get("phases") or {}).items())
    out += ["### Environment", "",
            table([[meta.get("machine", "?"), meta.get("testbeds", "?"), meta.get("scope", "?"),
                    "`%s`" % str(meta.get("image_sha256", "?"))[:12], "`%s`" % str(meta.get("sonic_mgmt", "?"))[:10], phases]],
                  ["machine", "testbeds", "scope", "image sha256", "sonic-mgmt", "phases"]), ""]
    return "\n".join(out)


def describe(outcome, new, not_run, infra, totals):
    if outcome == "infrastructure":
        return "Infrastructure: " + infra
    if outcome == "regressions":
        return "%d new failures" % len(new)
    if outcome == "incomplete":
        return "%d files not run; no new failures" % len(not_run)
    return "%d passed; no new failures" % totals["passed"]


def public(entry):
    return {k: entry[k] for k in ("id", "kind", "reason")}


def cmd_report(args):
    known = Known(args.known)
    meta = json.loads(Path(args.meta).read_text()) if args.meta and Path(args.meta).exists() else None
    infra = args.infra
    if not infra and meta is None:
        infra = "no run-meta.json came back"
    if not infra and meta.get("rc", 0) != 0:
        infra = "the harness exited with %s during %s" % (meta.get("rc"), meta.get("phase", "?"))
    first, final, ran = load_results(args.results, known.noise)
    new, covered, now_passing, stale = classify(final, known, ran)
    not_run = sorted(set(meta.get("files", [])) - ran) if meta else []
    outcome = decide(new, not_run, infra)
    totals = {k: sum(1 for c in final.values() if c.outcome == k) for k in ("passed", "skipped", "failed", "error")}
    totals["not_run_files"] = len(not_run)
    summary = {
        "outcome": outcome, "state": STATE[outcome], "title": TITLE[outcome],
        "description": describe(outcome, new, not_run, infra, totals), "infra": infra, "totals": totals,
        "new": [{"id": c, "outcome": final[c].outcome, "message": final[c].message} for c in new],
        "covered": [{"id": c, "outcome": final[c].outcome, "message": final[c].message} for c in covered],
        "now_passing": [public(e) for e in now_passing], "stale": [public(e) for e in stale],
        "rerun_passed": sorted(c for c in final if final[c].outcome == "passed" and first[c].outcome in BAD),
        "not_run": not_run, "meta": meta or {},
        "cases": {c: {"first": first[c].outcome, "final": final[c].outcome} for c in sorted(final)},
    }
    Path(args.out_json).write_text(json.dumps(summary, indent=1))
    Path(args.out_md).write_text(render(summary))
    Path(args.out_durations).write_text(json.dumps(durations(args.results), indent=1, sort_keys=True))


def cmd_rerun_files(args):
    known = Known(args.known)
    for test_file, cases in sorted(parse_dir(Path(args.chunk_dir), known.noise).items()):
        if any(c.outcome in BAD and not known.covers(cid, c) for cid, c in cases.items()):
            print(test_file)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    rerun = sub.add_parser("rerun-files")
    rerun.add_argument("--chunk-dir", required=True)
    rerun.add_argument("--known", required=True)
    rep = sub.add_parser("report")
    for opt in ("--results", "--known", "--out-json", "--out-md", "--out-durations"):
        rep.add_argument(opt, required=True)
    rep.add_argument("--meta")
    rep.add_argument("--infra", default="")
    args = parser.parse_args(argv)
    {"rerun-files": cmd_rerun_files, "report": cmd_report}[args.cmd](args)


if __name__ == "__main__":
    main()
```

- [ ] **第 4 步：运行测试，确认通过**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
预期：`21 passed`。

- [ ] **第 5 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/verdict.py .github/testflinger/t0/tests/test_verdict.py
git -C $W commit -m "test: judge t0 results against the known-failures list

A failure the list does not cover makes the run red; missing files make
it incomplete; a missing run-meta.json, a non-zero harness exit or a
failed provision make it an infrastructure problem. Reruns are chosen
from uncovered failures only. Durations add each chunk's unaccounted
wall time (pytest collection) evenly to its files.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 4：sonic-mgmt 测试床配置

**文件：**
- 新建：`.github/testflinger/t0/configure_sonic_mgmt.py`
- 测试：`.github/testflinger/t0/tests/test_configure_sonic_mgmt.py`

**接口：**
- 产出：`set_creds(text, user, password) -> str`；`set_inventory(text, user) -> str`；`set_server(text) -> str`；`main(root, user, password)`；CLI `configure_sonic_mgmt.py <sonic-mgmt dir> <user> <password>`。

- [ ] **第 1 步：编写会失败的测试**

`.github/testflinger/t0/tests/test_configure_sonic_mgmt.py`：

```python
import pytest

import configure_sonic_mgmt as cfg

CREDS = ("ptf_host_user: root\n\nvm_host_user: use_own_value\nvm_host_password: use_own_value\n"
         "vm_host_become_password: use_own_value\n\ncsonic_image: docker-sonic-vs\n")
VEOS = """all:
  children:
    lab:
      hosts:
        vlab-01:
          ansible_host: 10.250.0.101

          ansible_password: password
          ansible_user: admin
        vlab-02:
          ansible_user: admin
          ansible_python_interpreter: /usr/bin/python3
vm_host_1:
  hosts:
    STR-ACS-VSERV-01:
      ansible_host: 172.17.0.1
      ansible_user: use_own_value
      vm_host_user: use_own_value
"""
PY = "ansible_python_interpreter: /usr/bin/python3"


def test_set_creds_replaces_the_three_keys():
    out = cfg.set_creds(CREDS, "tb", "s3cret")
    assert "vm_host_user: tb\nvm_host_password: s3cret\nvm_host_become_password: s3cret\n" in out
    assert "use_own_value" not in out and "csonic_image: docker-sonic-vs" in out


def test_set_creds_fails_when_a_key_is_missing():
    with pytest.raises(ValueError):
        cfg.set_creds("vm_host_user: x\n", "tb", "p")


def test_set_inventory_adds_interpreter_once_and_sets_the_server_user():
    out = cfg.set_inventory(VEOS, "tb")
    assert "          ansible_user: admin\n          %s\n        vlab-02:" % PY in out
    assert out.count(PY) == 2
    assert "      ansible_user: tb\n      vm_host_user: tb\n" in out
    assert cfg.set_inventory(out, "tb") == out


def test_set_server_appends_interpreter_once():
    out = cfg.set_server("internal_mgmt_port: True\n")
    assert out == "internal_mgmt_port: True\n\n%s\n" % PY
    assert cfg.set_server(out) == out


def test_main_edits_the_tree(tmp_path):
    a = tmp_path / "ansible"
    (a / "group_vars" / "all").mkdir(parents=True)
    (a / "group_vars" / "vm_host").mkdir(parents=True)
    (a / "host_vars").mkdir()
    (a / "group_vars" / "all" / "creds.yml").write_text(CREDS)
    (a / "group_vars" / "vm_host" / "creds.yml").write_text(CREDS)
    (a / "veos_vtb").write_text(VEOS)
    (a / "host_vars" / "STR-ACS-VSERV-01.yml").write_text("internal_mgmt_port: True\n")
    cfg.main(str(tmp_path), "tb", "pw")
    assert (a / "password.txt").read_text() == "abc\n"
    assert "vm_host_user: tb" in (a / "group_vars" / "vm_host" / "creds.yml").read_text()
    assert PY in (a / "host_vars" / "STR-ACS-VSERV-01.yml").read_text()
```

- [ ] **第 2 步：运行测试，确认失败**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_configure_sonic_mgmt.py`
预期：FAIL，报 `ModuleNotFoundError: No module named 'configure_sonic_mgmt'`。

- [ ] **第 3 步：编写 `configure_sonic_mgmt.py`**

```python
#!/usr/bin/env python3
"""Apply the KVM testbed settings of the upstream guide to a sonic-mgmt tree.

usage: configure_sonic_mgmt.py <sonic-mgmt dir> <vm host user> <vm host password>
"""
import re
import sys
from pathlib import Path

PY = "ansible_python_interpreter: /usr/bin/python3"


def set_creds(text, user, password):
    for key, value in (("vm_host_user", user), ("vm_host_password", password), ("vm_host_become_password", password)):
        text, count = re.subn(r"(?m)^%s:.*$" % key, "%s: %s" % (key, value), text)
        if count != 1:
            raise ValueError("expected one %s line, found %d" % (key, count))
    return text


def set_inventory(text, user):
    text = re.sub(r"(?m)^([ \t]+)ansible_user: admin\n(?!\1%s)" % re.escape(PY),
                  lambda m: "%sansible_user: admin\n%s%s\n" % (m.group(1), m.group(1), PY), text)
    return re.sub(r"(?m)^([ \t]+)(ansible_user|vm_host_user): use_own_value$",
                  lambda m: "%s%s: %s" % (m.group(1), m.group(2), user), text)


def set_server(text):
    return text if PY in text else text.rstrip("\n") + "\n\n" + PY + "\n"


def main(root, user, password):
    ansible = Path(root) / "ansible"
    for creds in (ansible / "group_vars/all/creds.yml", ansible / "group_vars/vm_host/creds.yml"):
        creds.write_text(set_creds(creds.read_text(), user, password))
    inventory = ansible / "veos_vtb"
    inventory.write_text(set_inventory(inventory.read_text(), user))
    server = ansible / "host_vars/STR-ACS-VSERV-01.yml"
    server.write_text(set_server(server.read_text()))
    (ansible / "password.txt").write_text("abc\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
```

- [ ] **第 4 步：运行测试确认通过，再检查真实的目录树**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_configure_sonic_mgmt.py`
预期：`5 passed`。

然后把它应用到锁定版本 sonic-mgmt 的一份干净副本上，与 2026-11-19 实际可用的配置对比：

```bash
d=$(mktemp -d) && git -C ~/scratch/pr2-split/run2 archive a88d1d5f9323833d8cf2e050c84904deb22ed3bc ansible | tar -x -C $d
python3 ~/scratch/wt-t0/.github/testflinger/t0/configure_sonic_mgmt.py $d tb pw
diff <(git -C ~/scratch/pr2-split/run2 diff -U0 -- ansible/veos_vtb | grep '^[+-] ' | sed 's/sheldon-qi/tb/') \
     <(diff -U0 <(git -C ~/scratch/pr2-split/run2 show a88d1d5f9323833d8cf2e050c84904deb22ed3bc:ansible/veos_vtb) $d/ansible/veos_vtb | grep '^[+-] ')
rm -rf $d
```

预期：没有输出，或者只多出 `vlab-01` 以外的 DUT 主机下的 `+ … ansible_python_interpreter: /usr/bin/python3` 行（无害：t0 测试床只用 `vlab-01`）。`vlab-01` 的 interpreter 行和 `STR-ACS-VSERV-01` 的两行用户设置必须与 2026-11-19 的目录树一致。

- [ ] **第 5 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/configure_sonic_mgmt.py .github/testflinger/t0/tests/test_configure_sonic_mgmt.py
git -C $W commit -m "test: apply the KVM testbed settings to a sonic-mgmt tree

The VM host login, python3 for the DUT hosts and the server, and the
git-ignored vault password file: the edits the upstream vs testbed
guide asks for, matching the tree used on 2026-11-19.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 5：job 模板和 agent 端

**文件：**
- 新建：`.github/testflinger/t0/job.yaml.in`
- 新建：`.github/testflinger/t0/render_job.py`
- 新建：`.github/testflinger/t0/agent.sh`
- 测试：`.github/testflinger/t0/tests/test_render_job.py`
- 测试：`.github/testflinger/t0/tests/test_shell_syntax.py`

**接口：**
- 产出：`render_job.render(sha12, gh_run, image_url, image_sha256, scope, ghcr_user) -> str`；CLI `render_job.py --sha12 --gh-run --image-url --image-sha256 --scope --ghcr-user`（job YAML 输出到 stdout）。`agent.sh` 读取 `DEVICE_IP`、`GHCR_TOKEN`、`IMAGE_URL`、`IMAGE_SHA256`、`SCOPE`、`GHCR_USER`；需要 `attachments/test/t0-harness.tar.gz`；写出 `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log}`；以测试脚本的退出码退出。
- 使用（来自任务 6，在测试机上）：`~/t0/run-t0.sh` 写出 `~/t0-out/progress.log` 和 `~/t0-out/EXIT`。

- [ ] **第 1 步：编写会失败的测试**

`.github/testflinger/t0/tests/test_render_job.py`：

```python
import subprocess

import pytest
import yaml

import render_job

ARGS = dict(sha12="0123456789ab", gh_run="42",
            image_url="https://github.com/canonical/sonic-buildimage/releases/download/t0-images/sonic-vs-0123456789ab.img.gz",
            image_sha256="a" * 64, scope="smoke", ghcr_user="xdqi")


def test_render_gives_a_valid_job():
    job = yaml.safe_load(render_job.render(**ARGS))
    assert job["job_queue"] == "sonic-ci-large"
    assert job["global_timeout"] == 43200 and job["output_timeout"] == 7200
    assert job["provision_data"] == {"distro": "resolute"}
    assert job["test_data"]["secrets"] == {"GHCR_TOKEN": "sonic-buildimage/ghcr-read-token"}
    assert job["test_data"]["attachments"] == [{"local": "t0-harness.tar.gz"}]
    assert "sha:0123456789ab" in job["tags"] and "gh-run:42" in job["tags"]
    cmds = job["test_data"]["test_cmds"]
    assert "SCOPE='smoke'" in cmds and ARGS["image_url"] in cmds
    subprocess.run(["bash", "-n"], input=cmds, text=True, check=True)


@pytest.mark.parametrize("field,value", [("scope", "all"), ("image_url", "http://example.com/x"),
                                         ("image_url", "https://example.com/it's"), ("sha12", "XYZ"),
                                         ("image_sha256", "abc"), ("gh_run", "12a"), ("ghcr_user", "a b")])
def test_render_rejects_bad_values(field, value):
    with pytest.raises(ValueError):
        render_job.render(**dict(ARGS, **{field: value}))
```

`.github/testflinger/t0/tests/test_shell_syntax.py`：

```python
import subprocess
from pathlib import Path

import pytest

T0 = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("script", sorted(p.name for p in T0.glob("*.sh")))
def test_shell_syntax(script):
    subprocess.run(["bash", "-n", str(T0 / script)], check=True)
```

- [ ] **第 2 步：运行测试，确认失败**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_render_job.py .github/testflinger/t0/tests/test_shell_syntax.py`
预期：FAIL，报 `ModuleNotFoundError: No module named 'render_job'`（shell 测试此时还收集不到用例）。

- [ ] **第 3 步：编写模板、渲染脚本和 `agent.sh`**

`.github/testflinger/t0/job.yaml.in`：

```yaml
job_queue: sonic-ci-large
global_timeout: 43200
output_timeout: 7200
tags:
  - sonic-buildimage-t0
  - "sha:${SHA12}"
  - "gh-run:${GH_RUN}"
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GHCR_TOKEN: sonic-buildimage/ghcr-read-token
  test_cmds: |
    set -u
    mkdir -p t0 && tar -xzf attachments/test/t0-harness.tar.gz -C t0
    IMAGE_URL='${IMAGE_URL}' IMAGE_SHA256='${IMAGE_SHA256}' SCOPE='${SCOPE}' GHCR_USER='${GHCR_USER}' bash t0/agent.sh
```

`.github/testflinger/t0/render_job.py`：

```python
#!/usr/bin/env python3
"""Render job.yaml.in into a Testflinger job file on stdout."""
import argparse
import re
import string
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent / "job.yaml.in"


def render(sha12, gh_run, image_url, image_sha256, scope, ghcr_user):
    checks = [(re.fullmatch(r"[0-9a-f]{12}", sha12), "sha12"), (re.fullmatch(r"\d+", gh_run), "gh-run"),
              (re.fullmatch(r"https://[^'\s]+", image_url), "image-url"),
              (re.fullmatch(r"[0-9a-f]{64}", image_sha256), "image-sha256"),
              (scope in ("full", "smoke"), "scope"), (re.fullmatch(r"[A-Za-z0-9-]+", ghcr_user), "ghcr-user")]
    for ok, name in checks:
        if not ok:
            raise ValueError("invalid --%s" % name)
    return string.Template(TEMPLATE.read_text()).substitute(
        SHA12=sha12, GH_RUN=gh_run, IMAGE_URL=image_url, IMAGE_SHA256=image_sha256, SCOPE=scope, GHCR_USER=ghcr_user)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ("--sha12", "--gh-run", "--image-url", "--image-sha256", "--scope", "--ghcr-user"):
        parser.add_argument(opt, required=True)
    a = parser.parse_args(argv)
    sys.stdout.write(render(a.sha12, a.gh_run, a.image_url, a.image_sha256, a.scope, a.ghcr_user))


if __name__ == "__main__":
    main()
```

`.github/testflinger/t0/agent.sh`：

```bash
#!/bin/bash
# Agent side of the resolute t0 job: start the harness detached on the machine, relay progress, fetch the results.
set -u
opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30
      -o ServerAliveInterval=60 -o LogLevel=ERROR)
m=ubuntu@$DEVICE_IP
on() { ssh "${opts[@]}" "$m" "$@"; }
mkdir -p artifacts
scp "${opts[@]}" attachments/test/t0-harness.tar.gz "$m:t0-harness.tar.gz" || exit 1
on 'rm -rf t0 t0-out && mkdir -p t0 t0-out && tar -xzf t0-harness.tar.gz -C t0' || exit 1
# The token reaches the detached harness through stdin and its environment, never a command line.
printf '%s\n' "${GHCR_TOKEN:-}" | on "read -r GHCR_TOKEN; export GHCR_TOKEN IMAGE_URL='$IMAGE_URL' \
IMAGE_SHA256='$IMAGE_SHA256' SCOPE='$SCOPE' GHCR_USER='$GHCR_USER'; \
setsid nohup bash t0/run-t0.sh > t0-out/run-t0.log 2>&1 < /dev/null &" || exit 1
seen=0
while :; do
    sleep 60
    finished=no
    on 'test -e t0-out/EXIT' && finished=yes
    if new=$(on "tail -n +$((seen + 1)) t0-out/progress.log 2>/dev/null") && [ -n "$new" ]; then
        printf '%s\n' "$new"
        seen=$((seen + $(printf '%s\n' "$new" | wc -l)))
    fi
    [ "$finished" = yes ] && break
done
for f in results.tar.zst run-meta.json run-t0.log host-setup.log; do
    scp "${opts[@]}" "$m:t0-out/$f" artifacts/ || true
done
rc=$(on 'cat t0-out/EXIT' 2>/dev/null)
exit "${rc:-1}"
```

- [ ] **第 4 步：运行测试，确认通过**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
预期：`35 passed`（21 + 5 + 8 个渲染用例 + 1 个 shell 语法用例）。

- [ ] **第 5 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/job.yaml.in .github/testflinger/t0/render_job.py .github/testflinger/t0/agent.sh \
    .github/testflinger/t0/tests/test_render_job.py .github/testflinger/t0/tests/test_shell_syntax.py
git -C $W commit -m "test: Testflinger job template and agent side of the t0 run

The harness runs detached on the machine so an SSH drop cannot end the
run; the agent relays progress.log every minute, which also keeps the
output timeout quiet. GHCR_TOKEN goes over stdin into the harness
environment. Template values are validated, so none can carry a quote
into test_cmds.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 6：测试机端 —— 宿主机准备、测试床工作脚本、入口脚本、数据文件

**文件：**
- 新建：`.github/testflinger/t0/host-setup.sh`
- 新建：`.github/testflinger/t0/tb-run.sh`
- 新建：`.github/testflinger/t0/run-t0.sh`
- 新建：`.github/testflinger/t0/known-failures.yaml`
- 新建：`.github/testflinger/t0/sonic-mgmt.ref`
- 新建：`.github/testflinger/t0/smoke.txt`
- 测试：`.github/testflinger/t0/tests/test_shell_syntax.py`（已按 `*.sh` 参数化）

**接口：**
- 使用：`make_chunks.py` CLI（任务 1）；`verdict.py rerun-files`（任务 3）；`configure_sonic_mgmt.py` CLI（任务 4）；来自 `agent.sh` 的环境变量（任务 5）。
- 产出：`host-setup.sh` 的最后几行打印 `TESTBEDS=<n>`、`VCPU=<n>`、`POOL=<name>`；`run-t0.sh` 写出 `~/t0-out/{progress.log,host-setup.log,tb-<i>.log,files.txt,run-meta.json,results.tar.zst,EXIT}`；`run-meta.json` 的键为 `machine, testbeds, image_url, image_sha256, sonic_mgmt, scope, files, phases, time_guard, rc, phase`；结果放在 `/srv/queue/results/<label>/<NNN[.retry][.rerun]>/` 下，另有 `<NNN[.retry]>.time` = `<start> <end>`，即首次运行的起止时间（epoch 秒）。

- [ ] **第 1 步：编写 `host-setup.sh`**

```bash
#!/bin/bash
# Prepare the reserved machine for the testbed VMs; the last lines are TESTBEDS=, VCPU= and POOL=.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
S=/srv/share
sudo apt-get update -q
sudo apt-get install -y -q docker.io zfsutils-linux zstd python3-yaml >/dev/null
sudo snap install lxd 2>/dev/null || sudo snap refresh lxd || true
sudo lxc storage show default >/dev/null 2>&1 || sudo lxd init --auto --storage-backend dir
root_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")
spare=$(lsblk -dbn -o NAME,TYPE,SIZE,ROTA | awk -v r="$root_disk" '$2 == "disk" && $1 != r && $3 >= 200e9 && $4 == 0 {print "/dev/" $1}' | xargs)
if [ -n "$spare" ]; then
    # shellcheck disable=SC2086
    sudo zpool list tbpool >/dev/null 2>&1 || sudo zpool create -f tbpool $spare
    echo $((8 << 30)) | sudo tee /sys/module/zfs/parameters/zfs_arc_max >/dev/null
    sudo lxc storage show tb >/dev/null 2>&1 || sudo lxc storage create tb zfs source=tbpool
    pool=tb
    pool_gb=$(( $(sudo zpool list -Hp -o free tbpool) / 1000000000 ))
else
    pool=default
    pool_gb=$(( $(df -B1 --output=avail /var/snap/lxd/common/lxd/storage-pools/default | tail -1) / 1000000000 ))
fi
# VM memory is shmem on the host and the VM limits nearly fill RAM.
[ -f /swapfile-host ] || { sudo fallocate -l 64G /swapfile-host && sudo chmod 600 /swapfile-host && sudo mkswap /swapfile-host >/dev/null; }
swapon --show | grep -q /swapfile-host || sudo swapon /swapfile-host
# docker sets the FORWARD policy to DROP, which leaves the LXD VMs without network.
sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo mkdir -p $S /srv/queue
sudo chown ubuntu:ubuntu $S
sudo chmod 1777 /srv/queue
proxy=$(cat /etc/apt/apt.conf /etc/apt/apt.conf.d/* 2>/dev/null | grep -oP 'Acquire::http::Proxy "http://\K[^/"]+' | head -1 || true)
[ -n "$proxy" ] || { echo "no apt proxy configured on the host"; exit 1; }
echo "$proxy" > $S/apt-proxy
for img in docker-sonic-mgmt docker-ptf; do
    sudo docker pull -q sonicdev-microsoft.azurecr.io:443/$img:latest
    sudo docker save sonicdev-microsoft.azurecr.io:443/$img:latest -o $S/$img.tar
done
sudo chown ubuntu:ubuntu $S/*.tar
mem=$(free -g | awk '/^Mem:/{print $2}')
cpu=$(nproc)
t=$(( (mem - 16) / 18 ))
if [ $(( cpu / 8 )) -lt $t ]; then t=$(( cpu / 8 )); fi
if [ $(( pool_gb / 40 )) -lt $t ]; then t=$(( pool_gb / 40 )); fi
[ "$t" -ge 1 ] || { echo "machine too small: mem=${mem}G cpu=$cpu pool=${pool_gb}G"; exit 1; }
echo "TESTBEDS=$t"
echo "VCPU=$(( cpu / t ))"
echo "POOL=$pool"
```

- [ ] **第 2 步：编写 `tb-run.sh`**

```bash
#!/bin/bash
# One vms-kvm-t0 testbed in an LXD VM, then chunks from /srv/queue; usage: tb-run.sh <label> (as root).
set -euxo pipefail
LABEL=$1
U=tb H=/home/tb S=/srv/share Q=/srv/queue TB=vms-kvm-t0 DUT=vlab-01
R=$Q/results/$LABEL
mkdir -p "$R" $Q/claimed $Q/done $Q/finished
current=""
finish() {
    local rc=$?
    if [ -n "$current" ] && [ -f "$Q/claimed/$current.$LABEL" ]; then
        case $current in
            *.retry) mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL" ;;
            *) mv "$Q/claimed/$current.$LABEL" "$Q/pending/$current.retry" ;;
        esac
    fi
    echo "$rc" > "$Q/finished/$LABEL"
}
trap finish EXIT
export DEBIAN_FRONTEND=noninteractive
# The LXD VM image keeps a 70G root partition on the 140G disk.
growpart /dev/sda 1 || true
resize2fs /dev/sda1 || true
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
fi
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
set +x
echo "$U:$(cat $S/tb-pass)" | chpasswd
set -x
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
echo "Acquire::http::Proxy \"http://$(cat $S/apt-proxy)/\";" > /etc/apt/apt.conf.d/90proxy
# vm_set installs docker-ce with apt-key, gone in 26.04, unless a docker apt source already exists.
install -d -m 0755 /etc/apt/keyrings
[ -s /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
# A daily upgrade restarts openvswitch, which drops the testbed flows.
systemctl disable --now apt-daily-upgrade.timer apt-daily.timer unattended-upgrades >/dev/null 2>&1 || true
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io libvirt-daemon-system qemu-system-x86 openvswitch-switch \
    bridge-utils j2cli sshpass net-tools ethtool python3-pip python3-yaml xz-utils openssh-server >/dev/null
usermod -aG docker,libvirt,kvm $U
systemctl enable --now ssh docker libvirtd
# ovsdb-server first starts before the ovs-vswitchd alternative exists, and systemd stops retrying.
systemctl reset-failed ovsdb-server ovs-vswitchd openvswitch-switch || true
systemctl restart openvswitch-switch
ovs-vsctl show >/dev/null
mkdir -p $H/sonic-vm/images $H/veos-vm/images
[ -s $H/sonic-vm/images/sonic-vs.img ] || cp $S/sonic-vs.img $H/sonic-vm/images/sonic-vs.img
for t in ceos docker-sonic-mgmt docker-ptf; do docker load -q -i $S/$t.tar; done
docker image inspect publicmirror.azurecr.io:443/debian:trixie >/dev/null 2>&1 || docker pull -q publicmirror.azurecr.io:443/debian:trixie
[ -d $H/sonic-mgmt ] || cp -a $S/sonic-mgmt $H/sonic-mgmt
chown -R $U:$U $H
ip link show br1 >/dev/null 2>&1 || (cd $H/sonic-mgmt/ansible && ./setup-management-network.sh >/dev/null)
docker rm -f sonic-mgmt >/dev/null 2>&1 || true
su - $U -c "cd $H/sonic-mgmt && ./setup-container.sh -n sonic-mgmt -i sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest -d /data" | tail -3
mgmt() { docker exec --user $U sonic-mgmt bash -c "$1"; }
tbcli="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
mgmt "$tbcli add-topo $TB password.txt" > "$R/add-topo.log" 2>&1
mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/deploy-mg.log" 2>&1
echo "TESTBED READY $(date -Is)"
run_files() {
    local dir=$1
    shift
    mgmt "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUT -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -O -p logs/$dir -c '$*'" \
        > "$H/run_tests.log" 2>&1 || true
    mkdir -p "$R/$dir"
    cp -a "$H/sonic-mgmt/tests/logs/$dir/." "$R/$dir/" 2>/dev/null || true
    cp "$H/run_tests.log" "$R/$dir/run_tests.log"
}
while [ ! -e $Q/STOP ]; do
    current=""
    for p in "$Q"/pending/*; do
        [ -e "$p" ] || continue
        c=${p##*/}
        if mv "$p" "$Q/claimed/$c.$LABEL" 2>/dev/null; then current=$c; break; fi
    done
    [ -n "$current" ] || break
    mapfile -t files < "$Q/claimed/$current.$LABEL"
    start=$(date +%s)
    run_files "$current" "${files[@]}"
    echo "$start $(date +%s)" > "$R/$current.time"
    mapfile -t rerun < <(python3 $S/t0/verdict.py rerun-files --chunk-dir "$R/$current" --known $S/t0/known-failures.yaml)
    if [ "${#rerun[@]}" -gt 0 ]; then
        mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/$current.deploy-mg.log" 2>&1 || true
        run_files "$current.rerun" "${rerun[@]}"
    fi
    mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL"
    current=""
done
echo "QUEUE DONE $(date -Is)"
```

- [ ] **第 3 步：编写 `run-t0.sh`**

```bash
#!/bin/bash
# Machine side of the resolute t0 run, started detached by agent.sh; everything lands in ~/t0-out.
set -euo pipefail
T0=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/t0-out S=/srv/share Q=/srv/queue
CEOS=ghcr.io/canonical/sonic-ceos:4.32.5M-1
MGMT_IMAGE=sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest
START=$(date +%s)
DISPATCH_STOP=$((START + 37800))
HARD_STOP=$((START + 41400))
mkdir -p "$OUT"
: > "$OUT/progress.log"
phase=start phase_start=$START phases="" testbeds=0 time_guard=false
progress() { echo "$(date -u +%FT%TZ) $*" | tee -a "$OUT/progress.log"; }
enter() {
    local now
    now=$(date +%s)
    [ "$phase" = start ] || phases="$phases $phase=$((now - phase_start))"
    phase=$1 phase_start=$now
    progress "phase $phase"
}
finish() {
    local rc=$? failed=$phase
    set +e
    enter packing
    [ ! -d $Q/results ] || sudo tar -C $Q -cf - results | zstd -19 -T0 -q --force -o "$OUT/results.tar.zst"
    RC=$rc PHASE=$failed PHASES="$phases" TESTBEDS=$testbeds TIME_GUARD=$time_guard MGMT=$(cat "$T0/sonic-mgmt.ref") \
        python3 - "$OUT/files.txt" "$OUT/run-meta.json" <<'EOF'
import json, os, socket, sys
from pathlib import Path
files = Path(sys.argv[1]).read_text().split() if Path(sys.argv[1]).exists() else []
Path(sys.argv[2]).write_text(json.dumps({
    "machine": socket.gethostname(), "testbeds": int(os.environ["TESTBEDS"]),
    "image_url": os.environ.get("IMAGE_URL", ""), "image_sha256": os.environ.get("IMAGE_SHA256", ""),
    "sonic_mgmt": os.environ["MGMT"], "scope": os.environ.get("SCOPE", ""), "files": files,
    "phases": {k: int(v) for k, v in (p.split("=") for p in os.environ["PHASES"].split())},
    "time_guard": os.environ["TIME_GUARD"] == "true", "rc": int(os.environ["RC"]), "phase": os.environ["PHASE"]},
    indent=1))
EOF
    progress "exit $rc"
    echo "$rc" > "$OUT/EXIT"
}
trap finish EXIT
progress "start scope=$SCOPE image=$IMAGE_URL"

enter host-setup
bash "$T0/host-setup.sh" > "$OUT/host-setup.log" 2>&1
TESTBEDS=0 VCPU=0 POOL=default
eval "$(grep -E '^(TESTBEDS|VCPU|POOL)=[A-Za-z0-9_-]+$' "$OUT/host-setup.log")"
testbeds=$TESTBEDS
if [ "$SCOPE" = smoke ] && [ "$testbeds" -gt 2 ]; then testbeds=2; fi
progress "testbeds=$testbeds vcpu=$VCPU pool=$POOL"

enter payload
curl -fsSL --retry 5 -o $S/sonic-vs.img.gz "$IMAGE_URL"
echo "$IMAGE_SHA256  $S/sonic-vs.img.gz" | sha256sum -c -
gunzip -f $S/sonic-vs.img.gz
dc=$(mktemp -d -p /dev/shm)
printf '%s' "$GHCR_TOKEN" | sudo env DOCKER_CONFIG="$dc" docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null
sudo env DOCKER_CONFIG="$dc" docker pull -q $CEOS
sudo rm -rf "$dc"
unset GHCR_TOKEN
sudo docker tag $CEOS ceosimage:4.32.5M-1
sudo docker save ceosimage:4.32.5M-1 -o $S/ceos.tar
sudo chown ubuntu:ubuntu $S/ceos.tar
rm -rf $S/sonic-mgmt
mkdir -p $S/sonic-mgmt
curl -fsSL --retry 5 "https://codeload.github.com/canonical/sonic-mgmt/tar.gz/$(cat "$T0/sonic-mgmt.ref")" | tar -xz -C $S/sonic-mgmt --strip-components=1
openssl rand -hex 12 > $S/tb-pass
python3 "$T0/configure_sonic_mgmt.py" $S/sonic-mgmt tb "$(cat $S/tb-pass)"
rm -rf $S/t0
cp -a "$T0" $S/t0

enter test-list
if [ "$SCOPE" = smoke ]; then
    cp "$T0/smoke.txt" "$OUT/files.txt"
else
    sudo docker run --rm -v $S/sonic-mgmt:/sm:ro -w /sm/.azure-pipelines/impacted_area_testing $MGMT_IMAGE \
        python3 get_test_scripts.py --features "" --location /sm/tests \
        | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["t0_checker"]))' > "$OUT/files.txt"
fi
progress "$(wc -l < "$OUT/files.txt") test files"
sudo rm -rf $Q/pending $Q/claimed $Q/done $Q/finished $Q/results $Q/STOP
mkdir -p $Q/pending $Q/finished
target=3000
if [ "$SCOPE" = smoke ]; then target=1; fi
python3 "$T0/make_chunks.py" "$OUT/files.txt" "$T0/durations.json" $Q/pending $target

enter testbeds
for i in $(seq 1 "$testbeds"); do
    sudo lxc delete -f tb$i >/dev/null 2>&1 || true
    sudo lxc init ubuntu:26.04 tb$i --vm -s "$POOL" -c limits.cpu="$VCPU" -c limits.memory=18GiB -d root,size=140GiB
    sudo lxc config device add tb$i share disk source=$S path=$S readonly=true
    sudo lxc config device add tb$i queue disk source=$Q path=$Q
    sudo lxc start tb$i
done
for i in $(seq 1 "$testbeds"); do
    for _ in $(seq 120); do sudo lxc exec tb$i -- true 2>/dev/null && break; sleep 5; done
    if ! sudo lxc exec tb$i -- true 2>/dev/null; then
        echo "vm did not boot" > $Q/finished/tb$i
        progress "tb$i did not boot"
        continue
    fi
    setsid nohup sudo lxc exec tb$i -- bash $S/t0/tb-run.sh tb$i > "$OUT/tb-$i.log" 2>&1 < /dev/null &
    # Many lxc exec calls at once fail with "transient scope not created".
    sleep 5
done

enter tests
while :; do
    now=$(date +%s)
    progress "chunks pending=$(ls $Q/pending | wc -l) running=$(ls $Q/claimed | wc -l) done=$(ls $Q/done | wc -l); testbeds finished=$(ls $Q/finished | wc -l)/$testbeds"
    if [ "$(ls $Q/finished | wc -l)" -ge "$testbeds" ]; then break; fi
    if [ "$now" -ge $DISPATCH_STOP ] && [ ! -e $Q/STOP ]; then
        touch $Q/STOP
        time_guard=true
        progress "time guard: no new chunks from now on"
    fi
    if [ "$now" -ge $HARD_STOP ]; then
        progress "hard stop: packing the results that exist"
        break
    fi
    sleep 300
done
```

- [ ] **第 4 步：编写数据文件**

`.github/testflinger/t0/sonic-mgmt.ref`：

```
a88d1d5f9323833d8cf2e050c84904deb22ed3bc
```

`.github/testflinger/t0/smoke.txt`：

```
clock/test_clock.py
syslog/test_cron_health.py
tacacs/test_rw_user.py
arp/test_wr_arp.py
```

`.github/testflinger/t0/known-failures.yaml`：

```yaml
known: []
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- [ ] **第 5 步：运行测试和 shellcheck**

运行：`cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests && python3 -c "import sys; sys.path.insert(0, '.github/testflinger/t0'); import verdict; verdict.Known('.github/testflinger/t0/known-failures.yaml')"`
预期：`38 passed`（35 + 3 个新增的 shell 语法用例），加载清单时不报错。

运行：`docker run --rm -v ~/scratch/wt-t0/.github/testflinger/t0:/t0:ro koalaman/shellcheck:stable -S warning /t0/agent.sh /t0/host-setup.sh /t0/tb-run.sh /t0/run-t0.sh`
预期：没有输出。有任何警告都要在提交前修好。

- [ ] **第 6 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/host-setup.sh .github/testflinger/t0/tb-run.sh .github/testflinger/t0/run-t0.sh \
    .github/testflinger/t0/known-failures.yaml .github/testflinger/t0/sonic-mgmt.ref .github/testflinger/t0/smoke.txt
git -C $W commit -m "test: machine side of the t0 run on Testflinger

host-setup.sh, tb-run.sh and run-t0.sh are the 2026-11-10/19 farm
scripts made self-contained: the eight environment traps fixed in
place, VMs on spare SSDs (jasperoid's root disk holds only 10
testbeds), testbeds sized from RAM, threads and pool space, chunks
from a shared queue with a 10.5 h dispatch stop, reruns of uncovered
failures after deploy-mg, and a cEOS pull whose token only lives in
/dev/shm. The smoke list is four short files that all passed on rock
on 2026-11-19. sonic-mgmt is pinned to the head of PR stack #5-#9,
the commit of the 2026-11-19 full run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 7：一次性准备

**文件：** 不涉及仓库中的文件。

**接口：**
- 产出：`ghcr.io/canonical/sonic-ceos:4.32.5M-1`（internal）；一个带 `read:packages` 权限的 classic PAT，存放在 `~/.config/sonic-t0/ghcr-pat`（权限 600）；Testflinger secret `sonic-buildimage/ghcr-read-token`；仓库 secret `TESTFLINGER_CLIENT_ID` 和 `TESTFLINGER_SECRET_KEY`；在各 agent 上已生效的队列 `sonic-ci-large`。

- [ ] **第 1 步：推送 cEOS 镜像**

```bash
export DOCKER_CONFIG=$(mktemp -d)
gh auth token | docker login ghcr.io -u xdqi --password-stdin
docker tag ceosimage:4.32.5M-1 ghcr.io/canonical/sonic-ceos:4.32.5M-1
docker push ghcr.io/canonical/sonic-ceos:4.32.5M-1
docker logout ghcr.io; rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG
gh api /orgs/canonical/packages/container/sonic-ceos --jq .visibility
```

预期：push 以一行 `4.32.5M-1: digest: sha256:…` 结束，最后一条命令打印 `internal`。

- [ ] **第 2 步：请用户生成 PAT**

请用户打开 `https://github.com/settings/tokens/new?scopes=read:packages&description=sonic-ci-ghcr-read`，有效期选一年，生成 token，然后自己用下面的命令保存：

```bash
mkdir -p ~/.config/sonic-t0 && install -m 600 /dev/stdin ~/.config/sonic-t0/ghcr-pat
```

（粘贴 token，按回车，再按 Ctrl-D。）不要在聊天里索要 token。

- [ ] **第 3 步：验证 PAT 能拉取镜像**

```bash
export DOCKER_CONFIG=$(mktemp -d)
docker login ghcr.io -u xdqi --password-stdin < ~/.config/sonic-t0/ghcr-pat
docker pull ghcr.io/canonical/sonic-ceos:4.32.5M-1 | tail -2
docker logout ghcr.io; rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG
```

预期：先出现 `Login Succeeded`，然后是一行 `Digest: sha256:…`。如果登录失败，提示组织禁用了 classic token，就停下来报告用户：备选方案是机器人账号或 GitHub App（设计文档第 10 节）。

- [ ] **第 4 步：用 CI 凭据写入 Testflinger secret**

请用户把 CI 的 client id 和 secret key 分别保存为 `~/.config/sonic-t0/tf-client-id` 和 `~/.config/sonic-t0/tf-secret-key`（权限 600，同样用 `install -m 600 /dev/stdin` 的方法），然后执行：

```bash
testflinger-cli secret write --client-id "$(cat ~/.config/sonic-t0/tf-client-id)" \
    --secret-key "$(cat ~/.config/sonic-t0/tf-secret-key)" --expire-after -1 \
    sonic-buildimage/ghcr-read-token "$(cat ~/.config/sonic-t0/ghcr-pat)"
```

预期：退出状态为 0。

- [ ] **第 5 步：请用户添加仓库 secret**

由用户（仓库管理员）在 `canonical/sonic-buildimage` 的 Settings → Secrets and variables → Actions 下添加 `TESTFLINGER_CLIENT_ID` 和 `TESTFLINGER_SECRET_KEY`。然后检查：

```bash
gh secret list -R canonical/sonic-buildimage | grep -E '^TESTFLINGER_(CLIENT_ID|SECRET_KEY)'
```

预期：两个名字都列了出来。

- [ ] **第 6 步：检查队列**

```bash
testflinger-cli list-agents --fields name,status --filter-queues sonic-ci-large
```

预期：列出这 10 台机器（fleetroc、alarmmonkey、alienbunny、kroop、vlacq、cajal、parakarry、smilax、jasperoid、hoodin）。如果列表为空，告诉用户需要认证团队同步一次 TOR3-DH1（C3 里 10 台机器都已加上这个队列），然后继续做任务 8，它用不到这个队列。

---

### 任务 8：M1 —— 在一台机器上手动跑冒烟测试

**文件：** 如果测试暴露出 bug，就修改任务 5/6 的文件。

**接口：**
- 使用：测试脚本（任务 1–6）、PAT（任务 7）。

- [ ] **第 1 步：准备测试材料**

```bash
M1=~/scratch/t0-m1 && rm -rf $M1 && mkdir -p $M1/attachments/test
run=$(gh api "repos/canonical/sonic-buildimage/actions/workflows/resolute-build.yml/runs?branch=202605_resolute&event=push&status=success&per_page=1" --jq '.workflow_runs[0].id')
gh run download "$run" -R canonical/sonic-buildimage -n sonic-vs-img -D $M1/img
sha256sum $M1/img/sonic-vs.img.gz | cut -d' ' -f1 > $M1/img.sha256
tar -czf $M1/attachments/test/t0-harness.tar.gz -C ~/scratch/wt-t0/.github/testflinger/t0 --exclude=tests .
echo "build run $run, image $(cat $M1/img.sha256)"
```

- [ ] **第 2 步：预留 alarmmonkey（不用 reserve 阶段；占用 4 小时）**

写入 `~/testflinger-jobs/t0-m1-alarmmonkey.yaml`：

```yaml
job_queue: alarmmonkey
global_timeout: 43200
output_timeout: 8000
provision_data:
  distro: resolute
test_data:
  test_cmds: |
    SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30"
    $SSH ubuntu@$DEVICE_IP 'uname -a; nproc; free -g | head -2'
    $SSH ubuntu@$DEVICE_IP 'ssh-import-id lp:sheldon-qi gh:xdqi'
    echo "*** HOLD STARTED: ssh ubuntu@$DEVICE_IP ***"
    end=$((SECONDS + 14400))
    while [ $SECONDS -lt $end ]; do sleep 300; echo "hold: $(( (end - SECONDS) / 60 )) min left"; done
```

```bash
cd ~/testflinger-jobs && testflinger-cli submit --quiet t0-m1-alarmmonkey.yaml | tee t0-m1-jobid
```

轮询到日志出现 `HOLD STARTED`，记下 IP（在后台运行 `testflinger-cli poll $(cat t0-m1-jobid)`，或者用 `testflinger-cli status`）。

- [ ] **第 3 步：复制镜像，从本虚拟机运行 agent 端**

```bash
IP=<device ip from the hold line>
scp -o StrictHostKeyChecking=no ~/scratch/t0-m1/img/sonic-vs.img.gz ubuntu@$IP:sonic-vs.img.gz
cd ~/scratch/t0-m1 && DEVICE_IP=$IP GHCR_TOKEN=$(cat ~/.config/sonic-t0/ghcr-pat) \
  IMAGE_URL=file:///home/ubuntu/sonic-vs.img.gz IMAGE_SHA256=$(cat img.sha256) SCOPE=smoke GHCR_USER=xdqi \
  bash ~/scratch/wt-t0/.github/testflinger/t0/agent.sh > agent.log 2>&1; echo "agent exit $?"
```

在后台运行（`run_in_background`）；它每 5 分钟打印一行进度，大约 40–60 分钟结束。

- [ ] **第 4 步：判定结果**

```bash
cd ~/scratch/t0-m1 && rm -rf results && mkdir results && zstd -dc artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta artifacts/run-meta.json \
  --out-json summary.json --out-md report.md --out-durations durations.json
cat report.md; ls results; jq '.files, .testbeds, .rc, .phases' artifacts/run-meta.json
```

预期（M1 验收）：`agent exit 0`；`results/` 下有 `tb1` 和 `tb2`，各自至少有一个块目录；`smoke.txt` 中每个文件都有 JUnit 结果（没有 "Files not run"）；结论为 `Pass`。冒烟文件失败时要分析原因：要么是测试脚本的 bug（修复、提交，然后重复第 3 步 —— 在同一台机器上重跑 `run-t0.sh` 是安全的），要么是镜像真有问题（记下来，留给任务 11 的清单）。

- [ ] **第 5 步：提交修复并汇报**

每个测试脚本的修复单独提交，`test:` message 写明观察到的失败。向用户汇报：结论、`run-meta.json` 中的各阶段耗时，并说明 alarmmonkey 的占用（job id 在 `~/testflinger-jobs/t0-m1-jobid` 里）仍在运行，等用户说释放才释放。

---

### 任务 9：workflow

**文件：**
- 新建：`.github/workflows/resolute-t0.yml`

**接口：**
- 使用：`render_job.py` CLI、`verdict.py report` CLI、`known-failures.yaml`，以及任务 7 中的 Testflinger secret 和仓库 secret。
- 产出：commit 状态 `resolute-t0`；job summary；workflow artifact `resolute-t0-<sha12>-<attempt>`，内含 `summary.json`、`report.md`、`durations.json`、`artifacts/`；`t0-images` 中的 release 附件；带 `<!-- resolute-t0 -->` 标记的 PR 评论。

- [ ] **第 1 步：编写 workflow**

```yaml
name: resolute-t0

on:
  schedule:
    - cron: "0 15 * * *"
  workflow_run:
    workflows: [resolute-build]
    types: [completed]
  issue_comment:
    types: [created]
  workflow_dispatch:
    inputs:
      run_id:
        description: resolute-build run id to test (empty = latest successful push build of 202605_resolute)
        type: string
        default: ""
      scope:
        description: Test list
        type: choice
        options: [full, smoke]
        default: full
  push:
    branches: ["ci-workflow/t0-*"]

permissions:
  actions: read
  contents: write
  issues: write
  pull-requests: write
  statuses: write

env:
  GH_TOKEN: ${{ github.token }}
  REPO: ${{ github.repository }}
  GHCR_USER: xdqi

jobs:
  resolve:
    if: >-
      github.event_name != 'issue_comment' ||
      (github.event.issue.pull_request && startsWith(github.event.comment.body, '/test-t0'))
    runs-on: ubuntu-latest
    outputs:
      run_id: ${{ steps.r.outputs.run_id }}
      sha: ${{ steps.r.outputs.sha }}
      sha12: ${{ steps.r.outputs.sha12 }}
      status_sha: ${{ steps.r.outputs.status_sha }}
      known_ref: ${{ steps.r.outputs.known_ref }}
      scope: ${{ steps.r.outputs.scope }}
      pr: ${{ steps.r.outputs.pr }}
    steps:
      - name: Pick the build to test
        id: r
        env:
          EVENT: ${{ github.event_name }}
          WR_ID: ${{ github.event.workflow_run.id }}
          WR_OK: ${{ github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && (github.event.workflow_run.head_branch == '202605_resolute' || startsWith(github.event.workflow_run.head_branch, 'v')) }}
          IN_RUN: ${{ inputs.run_id }}
          IN_SCOPE: ${{ inputs.scope }}
          PR: ${{ github.event.issue.number }}
          COMMENT_ID: ${{ github.event.comment.id }}
          COMMENT: ${{ github.event.comment.body }}
          COMMENTER: ${{ github.event.comment.user.login }}
        run: |
          set -euo pipefail
          latest_push_build() {
            gh api "repos/$REPO/actions/workflows/resolute-build.yml/runs?branch=202605_resolute&event=push&status=success&per_page=1" \
              --jq '.workflow_runs[0].id // empty'
          }
          run_id="" scope=full pr="" known_ref="" status_sha=""
          say() { [ -z "$pr" ] || gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="resolute-t0: $1" >/dev/null; echo "$1"; }
          case "$EVENT" in
            workflow_run)
              if [ "$WR_OK" != true ]; then echo "not a successful push or tag build; nothing to test"; exit 0; fi
              run_id=$WR_ID ;;
            schedule) run_id=$(latest_push_build) ;;
            workflow_dispatch) run_id=${IN_RUN:-$(latest_push_build)}; scope=$IN_SCOPE ;;
            push)
              run_id=$(latest_push_build); known_ref=$GITHUB_SHA; status_sha=$GITHUB_SHA
              case "$GITHUB_REF_NAME" in ci-workflow/t0-full-*) scope=full ;; *) scope=smoke ;; esac ;;
            issue_comment)
              perm=$(gh api "repos/$REPO/collaborators/$COMMENTER/permission" --jq .permission 2>/dev/null || echo none)
              case "$perm" in admin|maintain|write) ;; *) echo "$COMMENTER has $perm permission; ignoring the comment"; exit 0 ;; esac
              gh api -X POST "repos/$REPO/issues/comments/$COMMENT_ID/reactions" -f content=eyes >/dev/null
              pr=$PR
              case "$(printf '%s\n' "$COMMENT" | head -1)" in *smoke*) scope=smoke ;; esac
              head=$(gh api "repos/$REPO/pulls/$PR" --jq .head.sha)
              run_id=$(gh api "repos/$REPO/actions/workflows/resolute-build.yml/runs?head_sha=$head&status=success&per_page=1" \
                --jq '.workflow_runs[0].id // empty')
              [ -n "$run_id" ] || { say "no successful resolute-build run for \`${head:0:12}\` yet; nothing to test."; exit 0; } ;;
          esac
          [ -n "$run_id" ] || { echo "no build to test"; exit 0; }
          sha=$(gh api "repos/$REPO/actions/runs/$run_id" --jq .head_sha)
          art=$(gh api "repos/$REPO/actions/runs/$run_id/artifacts" \
            --jq '[.artifacts[] | select(.name == "sonic-vs-img" and (.expired | not))][0].id // empty')
          [ -n "$art" ] || { say "build run $run_id has no unexpired sonic-vs-img artifact; nothing to test."; exit 0; }
          {
            echo "run_id=$run_id"; echo "sha=$sha"; echo "sha12=${sha:0:12}"; echo "scope=$scope"; echo "pr=$pr"
            echo "known_ref=${known_ref:-$sha}"; echo "status_sha=${status_sha:-$sha}"
          } >> "$GITHUB_OUTPUT"

  t0:
    needs: resolve
    if: needs.resolve.outputs.run_id != ''
    runs-on: [self-hosted-linux-amd64-noble-private-endpoint-small]
    timeout-minutes: 1440
    concurrency:
      group: resolute-t0-${{ needs.resolve.outputs.sha }}
      cancel-in-progress: false
    env:
      RUN_ID: ${{ needs.resolve.outputs.run_id }}
      SHA12: ${{ needs.resolve.outputs.sha12 }}
      STATUS_SHA: ${{ needs.resolve.outputs.status_sha }}
      KNOWN_REF: ${{ needs.resolve.outputs.known_ref }}
      SCOPE: ${{ needs.resolve.outputs.scope }}
      PR: ${{ needs.resolve.outputs.pr }}
      RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
      T0: .github/testflinger/t0
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: .github

      - name: Install tools
        run: |
          missing=()
          command -v gh >/dev/null || missing+=(gh)
          command -v zstd >/dev/null || missing+=(zstd)
          python3 -c 'import yaml, pytest' 2>/dev/null || missing+=(python3-yaml python3-pytest)
          [ "${#missing[@]}" -eq 0 ] || { sudo apt-get update -q && sudo apt-get install -y -q "${missing[@]}"; }

      - name: Unit tests of the harness
        run: python3 -m pytest -q "$T0/tests"

      - name: Mark the commit pending
        run: |
          gh api -X POST "repos/$REPO/statuses/$STATUS_SHA" -f state=pending -f context=resolute-t0 \
            -f target_url="$RUN_URL" -f description="t0 ($SCOPE) on Testflinger: running" >/dev/null

      - name: Download the vs image
        uses: actions/download-artifact@v4
        with:
          name: sonic-vs-img
          run-id: ${{ env.RUN_ID }}
          github-token: ${{ github.token }}
          path: img

      - name: Publish the image as a release asset
        id: img
        run: |
          set -euo pipefail
          name=sonic-vs-$SHA12.img.gz
          mv img/sonic-vs.img.gz "$name"
          sha256sum "$name" | cut -d' ' -f1 > "$name.sha256"
          gh release view t0-images -R "$REPO" >/dev/null 2>&1 || gh release create t0-images -R "$REPO" --prerelease \
            --title "t0 test images" --notes "vs images under test by the resolute-t0 workflow; only the newest 10 are kept."
          gh release upload t0-images -R "$REPO" --clobber "$name" "$name.sha256"
          gh api "repos/$REPO/releases/tags/t0-images" \
            --jq '[.assets[] | select(.name | endswith(".img.gz"))] | sort_by(.created_at) | reverse | .[10:][] | .name' |
            while read -r old; do
              gh release delete-asset t0-images "$old" -R "$REPO" -y
              gh release delete-asset t0-images "$old.sha256" -R "$REPO" -y || true
            done
          echo "url=https://github.com/$REPO/releases/download/t0-images/$name" >> "$GITHUB_OUTPUT"
          echo "sha256=$(cat "$name.sha256")" >> "$GITHUB_OUTPUT"
          rm -f "$name" "$name.sha256"

      - name: Chunk durations from the latest nightly run
        run: |
          set -uo pipefail
          echo '{}' > durations.json
          for id in $(gh run list -R "$REPO" -w resolute-t0.yml -e schedule -s completed -L 5 --json databaseId --jq '.[].databaseId'); do
            rm -rf prev
            if gh run download "$id" -R "$REPO" -p 'resolute-t0-*' -D prev 2>/dev/null; then
              f=$(find prev -name durations.json -size +2c | head -1)
              if [ -n "$f" ]; then cp "$f" durations.json; echo "durations from run $id"; break; fi
            fi
          done

      - name: Pack the harness and render the job
        env:
          IMAGE_URL: ${{ steps.img.outputs.url }}
          IMAGE_SHA256: ${{ steps.img.outputs.sha256 }}
        run: |
          set -euo pipefail
          rm -rf pack && mkdir pack
          cp -a "$T0/." pack/
          rm -rf pack/tests
          if gh api "repos/$REPO/contents/$T0/known-failures.yaml?ref=$KNOWN_REF" --jq .content > kf.b64 2>/dev/null; then
            base64 -d kf.b64 > pack/known-failures.yaml
          fi
          cp durations.json pack/durations.json
          tar -czf t0-harness.tar.gz -C pack .
          python3 "$T0/render_job.py" --sha12 "$SHA12" --gh-run "$GITHUB_RUN_ID" --image-url "$IMAGE_URL" \
            --image-sha256 "$IMAGE_SHA256" --scope "$SCOPE" --ghcr-user "$GHCR_USER" > job.yaml
          cat job.yaml

      - name: Run on Testflinger
        id: tf
        continue-on-error: true
        uses: canonical/testflinger/.github/actions/submit@257ef71c8042a41925d7185d46fc3171ea2112f5 # submit/v1.6.0
        with:
          poll: true
          job-path: job.yaml
          retries: 2
          client-id: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          secret-key: ${{ secrets.TESTFLINGER_SECRET_KEY }}

      - name: Fetch the Testflinger results
        if: always() && steps.tf.outputs.id != ''
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: |
          set -uo pipefail
          mkdir -p out/results
          testflinger results "$JOB_ID" > out/tf-results.json || true
          if testflinger artifacts --filename out/artifacts.tgz "$JOB_ID"; then
            tar -xzf out/artifacts.tgz -C out && rm -f out/artifacts.tgz
          fi
          if [ -f out/artifacts/results.tar.zst ]; then
            zstd -dc out/artifacts/results.tar.zst | tar -x -C out/results --strip-components=1
          fi

      - name: Judge
        id: verdict
        if: always()
        env:
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: |
          set -uo pipefail
          mkdir -p out/results
          infra=""
          if [ -z "$JOB_ID" ]; then
            infra="the Testflinger job was not submitted"
          elif [ "$(jq -r '.provision_status // 1' out/tf-results.json 2>/dev/null)" != 0 ]; then
            infra="provisioning failed after the retries"
          fi
          args=()
          [ ! -f out/artifacts/run-meta.json ] || args+=(--meta out/artifacts/run-meta.json)
          [ -z "$infra" ] || args+=(--infra "$infra")
          known=pack/known-failures.yaml
          [ -f "$known" ] || known=$T0/known-failures.yaml
          python3 "$T0/verdict.py" report --results out/results --known "$known" "${args[@]}" \
            --out-json out/summary.json --out-md out/report.md --out-durations out/durations.json
          cat out/report.md >> "$GITHUB_STEP_SUMMARY"
          echo "state=$(jq -r .state out/summary.json)" >> "$GITHUB_OUTPUT"
          echo "description=$(jq -r .description out/summary.json)" >> "$GITHUB_OUTPUT"

      - name: Upload the results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: resolute-t0-${{ env.SHA12 }}-${{ github.run_attempt }}
          path: |
            out/summary.json
            out/report.md
            out/durations.json
            out/artifacts/
          retention-days: 30
          if-no-files-found: warn

      - name: Report
        if: always()
        env:
          STATE: ${{ steps.verdict.outputs.state }}
          DESC: ${{ steps.verdict.outputs.description }}
        run: |
          set -uo pipefail
          state=${STATE:-error}
          desc=${DESC:-"resolute-t0 did not finish (cancelled or timed out)"}
          gh api -X POST "repos/$REPO/statuses/$STATUS_SHA" -f state="$state" -f context=resolute-t0 \
            -f target_url="$RUN_URL" -f description="${desc:0:140}" >/dev/null
          if [ -n "$PR" ]; then
            body="<!-- resolute-t0 -->"$'\n'"$(cat out/report.md 2>/dev/null || echo "$desc")"$'\n\n'"[Workflow run]($RUN_URL)"
            cid=$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
              --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- resolute-t0 -->"))) | .id' | tail -1)
            if [ -n "$cid" ]; then
              gh api -X PATCH "repos/$REPO/issues/comments/$cid" -f body="${body:0:65000}" >/dev/null
            else
              gh api -X POST "repos/$REPO/issues/$PR/comments" -f body="${body:0:65000}" >/dev/null
            fi
          fi
          [ "$state" = success ]
```

- [ ] **第 2 步：对 workflow 做 lint 检查**

运行：`docker run --rm -v ~/scratch/wt-t0:/repo:ro -w /repo rhysd/actionlint:latest -ignore 'label "self-hosted-linux-amd64-noble-private-endpoint-small" is unknown' .github/workflows/resolute-t0.yml`
预期：没有输出。提交前修好每一条问题（包括 `run:` 块里的 shellcheck 问题）。

- [ ] **第 3 步：提交**

```bash
W=~/scratch/wt-t0
git -C $W add .github/workflows/resolute-t0.yml
git -C $W commit -m "test: run sonic-mgmt t0 on Testflinger nightly, after builds and on /test-t0

One job on the small self-hosted runner follows the Testflinger job to
the end (self-hosted jobs may run 5 days; the 24 h timeout bounds the
queue wait). Comment triggers need write access, checked with the
collaborator permission API because event payloads show private org
members as CONTRIBUTOR. The machine-side scripts come from the default
branch; only the image and known-failures.yaml come from the commit
under test. ci-workflow/t0-* pushes run the smoke list for development.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### 任务 10：M2 —— workflow 端到端，冒烟

**文件：** 如果测试暴露出 bug，就修改任务 5/6/9 的文件（提交到 `feat/resolute-t0-testflinger`）。

**接口：**
- 使用：任务 1–9，以及任务 7 的准备工作，包括各 agent 上的 `sonic-ci-large` 队列。

- [ ] **第 1 步：推送一个不含构建 workflow 的开发分支**

```bash
W=~/scratch/wt-t0
git -C $W checkout -q -b ci-workflow/t0-m2
git -C $W rm -q .github/workflows/resolute-build.yml
git -C $W commit -q -m "test: development branch for the t0 workflow (drop resolute-build so the push does not build)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical ci-workflow/t0-m2
git -C $W checkout -q feat/resolute-t0-testflinger
gh run list -R canonical/sonic-buildimage --branch ci-workflow/t0-m2 -L 3
```

预期：一个 `resolute-t0` run，没有 `resolute-build` run。

- [ ] **第 2 步：跟踪这次 run**

在后台运行 `gh run watch <id> -R canonical/sonic-buildimage`。`t0` job 等 runner 约 9 分钟，然后装机约 20 分钟，冒烟测试约 40 分钟。不先问用户就不要取消它（AGENTS.md）。

- [ ] **第 3 步：检查 M2 验收**

```bash
c=$(git -C ~/scratch/wt-t0 rev-parse ci-workflow/t0-m2)
gh api repos/canonical/sonic-buildimage/commits/$c/statuses --jq '.[] | select(.context == "resolute-t0") | .state + " " + .description' | head -2
gh run view <id> -R canonical/sonic-buildimage --json jobs --jq '.jobs[] | .name + " " + .conclusion'
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m2 && ls -R ~/scratch/t0-m2 | head -30
```

预期：推送的 commit 上有 `resolute-t0` 状态（`success`，以及更早的 `pending`）；job summary 显示报告；artifact 中有 `summary.json`、`report.md`、`durations.json` 和 `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log}`；`summary.json` 与 `report.md`、Testflinger job 的输出彼此一致。

- [ ] **第 4 步：修复，然后清理**

每个修复都提交到 `feat/resolute-t0-testflinger`，再把 `ci-workflow/t0-m2` rebase 到它上面重新测试。M2 通过后删除该分支：

```bash
git -C ~/scratch/wt-t0 push -q canonical --delete ci-workflow/t0-m2
git -C ~/scratch/wt-t0 branch -D ci-workflow/t0-m2
```

---

### 任务 11：M3 —— 全量测试和第一版已知失败清单

**文件：**
- 修改：`.github/testflinger/t0/known-failures.yaml`

**接口：**
- 使用：workflow（任务 9）；`~/scratch/pr2-split/farm/analysis/rock-*` 和 `~/scratch/pr2-split/farm/compare-full-a88d1d5f9.txt` 中 2026-11-19 的 rock 版结果。

- [ ] **第 1 步：启动全量测试**

与任务 10 第 1 步相同，分支改用 `ci-workflow/t0-full-m3`（这个名字会选中 `scope=full`）。在后台跟踪；装机之后预计耗时 4–6 小时。

- [ ] **第 2 步：检查 M3 验收，收集失败**

```bash
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m3
jq '.outcome, .totals, .meta.phases, .meta.testbeds, (.new | length)' ~/scratch/t0-m3/*/summary.json
jq -r '.new[] | "\(.outcome)\t\(.id)\t\(.message)"' ~/scratch/t0-m3/*/summary.json > ~/scratch/t0-m3/new.tsv
wc -l ~/scratch/t0-m3/new.tsv
```

预期：在有 16 个测试床的机器上，tests 阶段 6 小时内跑完（测试床更少时，耗时按比例增加）；`.totals` 与 2026-11-19 的 rock 版测试接近（1219 通过、2654 跳过、31 失败、17 个 setup 错误）。

- [ ] **第 3 步：编写第一版清单**

对 `new.tsv` 的每一行，与同一用例在 2026-11-19 rock 版测试中的结果对比（`compare-full-a88d1d5f9.txt` 和 `farm/analysis/rock-*`）。然后：
- 2026-11-19 也因同样原因失败的用例，写成一条 `kind: fail` 或 `error` 的条目，英文 `reason` 取自 2026-11-19 的分析（例如 `"Process monitoring: rock stops the container when a critical service exits (PR #28 behaviour)"`）；
- 参数随机的一组参数化用例，写成一条带 `*`、`kind: flaky` 的条目（14 个 `generic_hash` 用例）；
- 2026-11-19 没有失败的用例，进清单之前先调查：新的镜像或环境问题要写明原因，否则就先修好。

运行 `python3 -m pytest -q .github/testflinger/t0/tests`，并在本地用新清单重新判定下载下来的 M3 结果：

```bash
cd ~/scratch/t0-m3 && mkdir -p results && zstd -dc */artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta */artifacts/run-meta.json \
  --out-json s.json --out-md r.md --out-durations d.json && jq '.outcome, (.new | length)' s.json
```

预期：`"pass"` 和 `0`。

- [ ] **第 4 步：提交并清理**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/known-failures.yaml
git -C $W commit -m "test: first known-failures list for the resolute t0 run

From the full run <workflow run id> at <image sha12>, compared case by
case with the rock run of 2026-11-19.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical --delete ci-workflow/t0-full-m3
git -C $W branch -D ci-workflow/t0-full-m3
```

（用第 2 步得到的 run id 和镜像 SHA 填好 message。）

---

### 任务 12：pull request 和 M4

**文件：** 没有新文件。

- [ ] **第 1 步：推送和开 pull request 之前先问用户**

得到用户同意后：

```bash
git -C ~/scratch/wt-t0 push -q canonical feat/resolute-t0-testflinger
gh pr create -R canonical/sonic-buildimage --base 202605_resolute --head feat/resolute-t0-testflinger \
  --title "test: run sonic-mgmt t0 on Testflinger nightly, after builds and on /test-t0" --body-file <body file>
```

PR 描述只写当前状态：什么时候跑什么、结果出现在哪里、已完成的一次性准备（任务 7）、M1–M3 的结果及 run 链接，以及如何维护 `known-failures.yaml` 和 `sonic-mgmt.ref`。结尾是 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`。

- [ ] **第 2 步：用户合入后，检查 M4**

```bash
gh run list -R canonical/sonic-buildimage -w resolute-t0.yml -L 10 --json databaseId,event,conclusion,createdAt
```

预期在大约一天内看到：一次 `schedule` run；合入 `202605_resolute` 之后的一次 `workflow_run` run；用户（或经用户同意后由 agent）在某个打开的 PR 上评论 `/test-t0 smoke` 之后的一次 `issue_comment` run。每次都有报告和 `resolute-t0` commit 状态，评论触发的那次还有带 `<!-- resolute-t0 -->` 标记的 PR 评论。

- [ ] **第 3 步：记录结果**

更新 memory 文件 `resolute-nightly-testflinger-design.md`：写入 PR 编号、M1–M4 的结果，以及这几次测试中学到、但代码里没有体现的东西。
