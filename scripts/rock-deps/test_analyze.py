# Tests for analyze.py (rock real-dependency analysis).
# Run: python3 -m pytest scripts/rock-deps/test_analyze.py -q
# Needs: python3, pytest, readelf (binutils); uses host /usr/bin/true and glibc as ELF fixtures.
import gzip
import os
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from analyze import (  # noqa: E402
    covering_slices,
    elf_needed_closure,
    load_contents,
    map_paths,
    parse_trace,
)

LIBDIR = "usr/lib/x86_64-linux-gnu"


def test_map_paths_uses_contents_and_marks_unknown():
    contents = {"usr/bin/redis-server": "database/redis-server"}
    assert map_paths({"/usr/bin/redis-server", "/usr/bin/sonic-db-cli"}, contents) == {
        "/usr/bin/redis-server": "redis-server",
        "/usr/bin/sonic-db-cli": None,
    }


def test_map_paths_follows_usrmerge_aliases():
    contents = {f"{LIBDIR}/libc.so.6": "libs/libc6"}
    assert map_paths({"/lib/x86_64-linux-gnu/libc.so.6"}, contents) == {
        "/lib/x86_64-linux-gnu/libc.so.6": "libc6"
    }


def test_load_contents_keeps_only_wanted_paths_and_first_package(tmp_path):
    f = tmp_path / "Contents-amd64.gz"
    with gzip.open(f, "wt") as out:
        out.write("usr/bin/ip                         net/iproute2\n")
        out.write("usr/bin/foo bar                    misc/a,misc/b\n")
        out.write("usr/bin/unwanted                   misc/c\n")
    got = load_contents([f], {"/usr/bin/ip", "/usr/bin/foo bar"})
    assert got == {"usr/bin/ip": "net/iproute2", "usr/bin/foo bar": "misc/a,misc/b"}
    assert map_paths({"/usr/bin/foo bar"}, got) == {"/usr/bin/foo bar": "a"}


def test_covering_slices_matches_globs():
    sdfs = {"libzmq5": {"slices": {"libs": {"contents": {"/usr/lib/*-linux-*/libzmq.so.5*": {}}}}}}
    assert covering_slices("/usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5", sdfs) == ["libzmq5_libs"]


def test_covering_slices_star_does_not_cross_slash_but_double_star_does():
    sdfs = {
        "p": {
            "slices": {
                "one": {"contents": {"/usr/share/p/*": {}}},
                "deep": {"contents": {"/usr/share/p/**": {}}},
            }
        }
    }
    assert covering_slices("/usr/share/p/a/b", sdfs) == ["p_deep"]
    assert sorted(covering_slices("/usr/share/p/a", sdfs)) == ["p_deep", "p_one"]


def test_trace_lines_relative_to_rootfs_and_ignore_proc_sys_dev():
    assert parse_trace(["OPEN /proc/1/stat", "EXEC /usr/bin/ip", "OPEN /dev/null"]) == {"/usr/bin/ip"}


def test_trace_ignores_relative_and_garbage_lines():
    assert parse_trace(["OPEN libfoo.so", "Attaching 2 probes...", "", "OPEN /etc/redis/redis.conf"]) == {
        "/etc/redis/redis.conf"
    }


def _mini_rootfs(tmp_path: Path, with_libc: bool) -> Path:
    root = tmp_path / "rootfs"
    (root / "usr/bin").mkdir(parents=True)
    (root / LIBDIR).mkdir(parents=True)
    shutil.copy("/usr/bin/true", root / "usr/bin/true")
    if with_libc:
        shutil.copy(os.path.realpath(f"/{LIBDIR}/libc.so.6"), root / LIBDIR / "libc.so.6")
        shutil.copy(os.path.realpath("/lib64/ld-linux-x86-64.so.2"), root / LIBDIR / "ld-linux-x86-64.so.2")
        (root / "usr/lib64").mkdir()
        os.symlink(f"/{LIBDIR}/ld-linux-x86-64.so.2", root / "usr/lib64/ld-linux-x86-64.so.2")
        os.symlink("usr/lib64", root / "lib64")
    return root


def test_elf_needed_closure_resolves_needed_and_interpreter(tmp_path):
    root = _mini_rootfs(tmp_path, with_libc=True)
    got = elf_needed_closure(root, {"/usr/bin/true"})
    assert f"/{LIBDIR}/libc.so.6" in got
    assert "/lib64/ld-linux-x86-64.so.2" in got
    assert not any(p.startswith("?") for p in got)


def test_elf_needed_closure_reports_missing_libs(tmp_path):
    root = _mini_rootfs(tmp_path, with_libc=False)
    assert "?libc.so.6" in elf_needed_closure(root, {"/usr/bin/true"})


def test_elf_needed_closure_ignores_non_elf_roots(tmp_path):
    root = _mini_rootfs(tmp_path, with_libc=True)
    (root / "usr/bin/script.sh").write_text("#!/bin/sh\n")
    assert elf_needed_closure(root, {"/usr/bin/script.sh", "/no/such"}) == set()


def test_main_reports_packages_slices_and_traced_paths_absent_from_rootfs(tmp_path):
    from analyze import main

    root = _mini_rootfs(tmp_path, with_libc=True)
    trace = tmp_path / "out" / "dut2" / "ctr" / "trace-run.txt"
    trace.parent.mkdir(parents=True)
    trace.write_text("EXEC /usr/bin/true\nOPEN /etc/only-on-dut2.conf\n")
    contents = tmp_path / "Contents-amd64"
    contents.write_text(f"usr/bin/true  utils/coreutils\n{LIBDIR}/libc.so.6  libs/libc6\n")
    release = tmp_path / "release"
    (release / "slices").mkdir(parents=True)
    (release / "slices" / "libc6.yaml").write_text(
        "package: libc6\nslices:\n  libs:\n    contents:\n      /usr/lib/*-linux-*/libc.so.*:\n")
    out = tmp_path / "deps.md"
    assert main(["--rootfs", str(root), "--trace", str(trace), "--contents", str(contents),
                 "--chisel-release", str(release), "--out", str(out)]) == 0
    text = out.read_text()
    assert "| libc6 |" in text and "libc6_libs" in text
    assert "| coreutils |" in text and "NO-SDF" in text
    assert "`/etc/only-on-dut2.conf` [broadcom]" in text


def test_elf_needed_closure_records_which_elf_needs_each_lib(tmp_path):
    root = _mini_rootfs(tmp_path, with_libc=True)
    why = {}
    elf_needed_closure(root, {"/usr/bin/true"}, why)
    assert "/usr/bin/true" in why[f"/{LIBDIR}/libc.so.6"]


def test_attribute_prefers_owner_already_evidenced_for_multi_owner_paths():
    from analyze import attribute

    contents = {"usr/bin/cat": "utils/coreutils-from-busybox,utils/gnu-coreutils",
                "usr/bin/gnucat": "utils/gnu-coreutils"}
    got = attribute({"/usr/bin/cat", "/usr/bin/gnucat"}, contents, self_built=set())
    assert got == {"/usr/bin/cat": "gnu-coreutils", "/usr/bin/gnucat": "gnu-coreutils"}


def test_attribute_marks_self_built_and_rock_injected_paths_as_non_archive():
    from analyze import attribute

    contents = {f"{LIBDIR}/libyang.so.3": "libs/libyang3", "usr/bin/pebble": "admin/pebble"}
    got = attribute({f"/{LIBDIR}/libyang.so.3", "/usr/bin/pebble"}, contents, self_built={"libyang3"})
    assert got == {f"/{LIBDIR}/libyang.so.3": None, "/usr/bin/pebble": None}


def test_recipe_self_built_debs_parsed_from_dpkg_x_lines(tmp_path):
    from analyze import recipe_self_built

    r = tmp_path / "rockcraft.yaml"
    r.write_text("parts:\n  p:\n    override-build: |\n      dpkg -x debs/libyang3_*.deb ${X}\n"
                 "      dpkg -x debs/python3-swsscommon_*.deb ${X}\n")
    assert recipe_self_built(r) == {"libyang3", "python3-swsscommon"}


def test_main_extra_roots_add_static_only_executables_and_their_libs(tmp_path):
    from analyze import main

    root = _mini_rootfs(tmp_path, with_libc=True)
    contents = tmp_path / "Contents-amd64"
    contents.write_text(f"usr/bin/true  utils/coreutils\n{LIBDIR}/libc.so.6  libs/libc6\n")
    release = tmp_path / "release"
    (release / "slices").mkdir(parents=True)
    out = tmp_path / "deps.md"
    assert main(["--rootfs", str(root), "--contents", str(contents), "--chisel-release", str(release),
                 "--extra-roots", "/usr/bin/true", "--out", str(out)]) == 0
    text = out.read_text()
    assert "| coreutils | 1: static-root /usr/bin/true |" in text
    assert "| libc6 |" in text


def test_main_lists_used_paths_no_slice_covers(tmp_path):
    from analyze import main

    root = _mini_rootfs(tmp_path, with_libc=True)
    (root / "etc").mkdir()
    (root / "etc/libc.conf").write_text("x")
    trace = tmp_path / "out" / "vs" / "ctr" / "trace-run.txt"
    trace.parent.mkdir(parents=True)
    trace.write_text("EXEC /usr/bin/true\nOPEN /etc/libc.conf\n")
    contents = tmp_path / "Contents-amd64"
    contents.write_text(f"usr/bin/true  utils/coreutils\n{LIBDIR}/libc.so.6  libs/libc6\netc/libc.conf  libs/libc6\n")
    release = tmp_path / "release"
    (release / "slices").mkdir(parents=True)
    (release / "slices" / "libc6.yaml").write_text(
        "package: libc6\nslices:\n  libs:\n    contents:\n      /usr/lib/*-linux-*/libc.so.*:\n")
    out = tmp_path / "deps.md"
    main(["--rootfs", str(root), "--trace", str(trace), "--contents", str(contents),
          "--chisel-release", str(release), "--out", str(out)])
    uncovered = out.read_text().split("## Used paths no slice covers", 1)[1]
    assert "`/etc/libc.conf` (libc6)" in uncovered
    assert "libc.so.6" not in uncovered.split("##", 1)[0]


def _release(tmp_path, sdfs):
    release = tmp_path / "release"
    (release / "slices").mkdir(parents=True)
    for pkg, text in sdfs.items():
        (release / "slices" / f"{pkg}.yaml").write_text(text)
    return release


def test_minimise_slices_drops_slices_pulled_in_by_essential(tmp_path):
    from analyze import minimise_slices

    release = _release(tmp_path, {
        # package-level essential applies to every slice; slice-level essential is transitive
        "app": "package: app\nessential:\n  - app_copyright\nslices:\n  bins:\n    essential:\n      - app_config\n"
               "  config:\n    essential:\n      - libfoo_libs\n  copyright: {}\n  extra: {}\n",
        "libfoo": "package: libfoo\nslices:\n  libs: {}\n",
    })
    got = minimise_slices(release, ["libfoo_libs", "app_config", "app_bins", "app_extra", "base_missing-sdf"])
    assert got == ["app_bins", "app_extra", "base_missing-sdf"]


def test_main_minimise_subcommand_prints_one_slice_per_line(tmp_path, capsys):
    from analyze import main

    release = _release(tmp_path, {"a": "package: a\nslices:\n  x:\n    essential:\n      - a_y\n  y: {}\n"})
    lst = tmp_path / "list.txt"
    lst.write_text("# comment\na_y\na_x\n")
    assert main(["minimise", "--chisel-release", str(release), str(lst)]) == 0
    assert capsys.readouterr().out == "a_x\n"


def test_main_maps_traced_pyc_to_its_source_module_slice(tmp_path):
    # CPython opens only __pycache__/<m>.cpython-XY.pyc; Contents and SDFs list <m>.py
    from analyze import main

    root = tmp_path / "rootfs"
    (root / "usr/lib/python3.14/__pycache__").mkdir(parents=True)
    (root / "usr/lib/python3.14/pprint.py").write_text("x")
    (root / "usr/lib/python3.14/__pycache__/pprint.cpython-314.pyc").write_text("x")
    trace = tmp_path / "out" / "vs" / "ctr" / "trace-run.txt"
    trace.parent.mkdir(parents=True)
    trace.write_text("OPEN /usr/lib/python3.14/__pycache__/pprint.cpython-314.pyc\n")
    contents = tmp_path / "Contents-amd64"
    contents.write_text("usr/lib/python3.14/pprint.py  python/libpython3.14-stdlib\n")
    release = _release(tmp_path, {"libpython3.14-stdlib": "package: libpython3.14-stdlib\nslices:\n  data-types:\n"
                                  "    contents:\n      /usr/lib/python3.14/pprint.py:\n"})
    out = tmp_path / "deps.md"
    main(["--rootfs", str(root), "--trace", str(trace), "--contents", str(contents),
          "--chisel-release", str(release), "--out", str(out)])
    table = out.read_text().split("\n## ")[0]
    assert "| libpython3.14-stdlib |" in table and "libpython3.14-stdlib_data-types" in table


def test_main_adds_shebang_interpreters_of_traced_scripts(tmp_path):
    # exec of a script is traced as the script only; the kernel loads its interpreter (and env's target) silently
    from analyze import main

    root = tmp_path / "rootfs"
    (root / "usr/bin").mkdir(parents=True)
    (root / "usr/local/bin").mkdir(parents=True)
    for name in ("env", "bash"):
        (root / "usr/bin" / name).write_text("x")
    init = root / "usr/local/bin/init.sh"
    init.write_text("#!/usr/bin/env bash\necho hi\n")
    init.chmod(0o755)
    module = root / "usr/local/bin/lib.py"  # not executable: its shebang is never used
    module.write_text("#!/usr/bin/python3\n")
    trace = tmp_path / "out" / "vs" / "ctr" / "trace-run.txt"
    trace.parent.mkdir(parents=True)
    trace.write_text("EXEC /usr/local/bin/init.sh\nOPEN /usr/local/bin/lib.py\n")
    contents = tmp_path / "Contents-amd64"
    contents.write_text("usr/bin/env  utils/coreutils\nusr/bin/bash  shells/bash\nusr/bin/python3  python/python3\n")
    release = _release(tmp_path, {
        "coreutils": "package: coreutils\nslices:\n  env:\n    contents:\n      /usr/bin/env:\n",
        "bash": "package: bash\nslices:\n  bins:\n    contents:\n      /usr/bin/bash:\n"})
    out = tmp_path / "deps.md"
    main(["--rootfs", str(root), "--trace", str(trace), "--contents", str(contents),
          "--chisel-release", str(release), "--out", str(out)])
    table = out.read_text().split("\n## ")[0]
    assert "coreutils_env" in table and "bash_bins" in table
    assert "python3" not in table
