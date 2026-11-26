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


def test_auto_target_gives_each_testbed_two_rounds():
    durations = {"f%02d.py" % i: 600 for i in range(40)}
    assert make_chunks.auto_target(list(durations), durations, testbeds=4) == 3000
    assert make_chunks.auto_target(["new.py"], {}, testbeds=1, default=480) == 240


def test_cli_auto_target(tmp_path):
    (tmp_path / "files.txt").write_text("".join("f%d.py\n" % i for i in range(8)))
    (tmp_path / "d.json").write_text(json.dumps({"f%d.py" % i: 100 for i in range(8)}))
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "d.json"), str(tmp_path / "out"), "auto", "480", "2"], check=True)
    assert len(list((tmp_path / "out").iterdir())) == 4
