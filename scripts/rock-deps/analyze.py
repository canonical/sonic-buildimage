#!/usr/bin/env python3
# Merge static (ELF DT_NEEDED) and dynamic (bpftrace) evidence of what a container really uses,
# map every used path to its Ubuntu archive package and to the chisel slices that cover it.
# Usage: analyze.py --rootfs rootfs.tar --trace <host>/<ctr>/trace-*.txt ... --contents Contents-amd64.gz ...
#                   --chisel-release ~/repos/chisel-releases [--recipe dockers/<d>/rockcraft.yaml] --out deps.md
#        analyze.py minimise --chisel-release <release> <slices.txt>   (drop slices implied by essential)
# Needs: python3 with PyYAML, readelf (binutils). Platform of a trace = its <host> dir (ROCKDEPS_PLATFORMS maps it).
import argparse
import gzip
import os
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
from collections import defaultdict
from pathlib import Path

import yaml

IGNORED_PREFIXES = ("/proc/", "/sys/", "/dev/")
DEFAULT_LIB_DIRS = ["/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu", "/lib", "/usr/lib", "/usr/local/lib"]
# usrmerge: the same file may be reached as /lib/x or /usr/lib/x; Contents only lists one of them
# Injected by rockcraft itself, never from a slice or a deb
ROCK_INJECTED = ("/usr/bin/pebble", "/.rock/", "/var/lib/pebble/")
USRMERGE_ALIASES = [("/lib64/", "/usr/lib64/"), ("/lib/", "/usr/lib/"), ("/bin/", "/usr/bin/"), ("/sbin/", "/usr/sbin/")]


def parse_trace(lines):
    """Return the absolute, package-relevant paths of `EXEC <path>` / `OPEN <path>` trace lines."""
    paths = set()
    for line in lines:
        kind, _, path = line.strip().partition(" ")
        if kind not in ("EXEC", "OPEN") or not path.startswith("/"):
            continue
        path = os.path.normpath(path)
        if path.startswith(IGNORED_PREFIXES) or path in ("/proc", "/sys", "/dev"):
            continue
        paths.add(path)
    return paths


def _aliases(path):
    yield path
    for short, full in USRMERGE_ALIASES:
        if path.startswith(short):
            yield full + path[len(short):]
        elif path.startswith(full):
            yield short + path[len(full):]


PYC_RE = re.compile(r"^(.*)/__pycache__/([^/]+?)\.cpython-\d+(?:\.opt-\d+)?\.pyc$")


def pyc_source(path):
    """/x/__pycache__/m.cpython-314.pyc -> /x/m.py: CPython opens only the .pyc, Contents and SDFs list the .py"""
    m = PYC_RE.match(path)
    return f"{m.group(1)}/{m.group(2)}.py" if m else None


SCRIPT_PATH = ("/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin")


def shebang_interpreters(root, path):
    """Interpreters the kernel loads for an executable script (and env's target): exec traces only show the script."""
    host = _in_root(root, path)
    try:
        if not host.is_file() or not host.stat().st_mode & 0o111:
            return []
        with open(host, "rb") as fh:
            first = fh.readline(256)
    except OSError:
        return []
    if not first.startswith(b"#!"):
        return []
    words = first[2:].decode(errors="replace").split()
    if not words:
        return []
    found = [words[0]]
    if os.path.basename(words[0]) == "env":
        args = [w for w in words[1:] if not w.startswith("-")]
        if args:
            found += [f"{d}/{args[0]}" for d in SCRIPT_PATH if _resolve(root, f"{d}/{args[0]}") is not None][:1]
    return found


def load_contents(files, wanted):
    """Read Ubuntu Contents-<arch>(.gz) files, keeping only entries for `wanted` paths (and their aliases)."""
    keys = {a.lstrip("/") for p in wanted for a in _aliases(p)}
    found = {}
    for f in files:
        opener = gzip.open if str(f).endswith(".gz") else open
        with opener(f, "rt", errors="replace") as fh:
            for line in fh:
                path, _, pkgs = line.rstrip("\n").rpartition(" ")
                path = path.rstrip()
                if path in keys and path not in found:
                    found[path] = pkgs.strip()
    return found


def map_paths(paths, contents):
    """Map each path to its archive package name, or None when no Contents entry exists."""
    result = {}
    for path in paths:
        pkg = None
        for alias in _aliases(path):
            entry = contents.get(alias.lstrip("/"))
            if entry:
                pkg = entry.split(",")[0].rsplit("/", 1)[-1]
                break
        result[path] = pkg
    return result


def _candidates(path, contents):
    for alias in _aliases(path):
        entry = contents.get(alias.lstrip("/"))
        if entry:
            return [e.rsplit("/", 1)[-1] for e in entry.split(",")]
    return []


def attribute(paths, contents, self_built):
    """Like map_paths, but None for rock-injected and self-built files, and a multi-owner path goes to an owner
    that already owns another used path (e.g. /usr/bin/cat -> gnu-coreutils when /usr/bin/gnucat is used)."""
    result, multi = {}, {}
    for path in paths:
        cands = _candidates(path, contents)
        if path.startswith(ROCK_INJECTED) or path in ROCK_INJECTED or any(c in self_built for c in cands):
            result[path] = None
        elif len(cands) > 1:
            multi[path] = cands
        else:
            result[path] = cands[0] if cands else None
    owned = {v for v in result.values() if v}
    for path, cands in multi.items():
        result[path] = next((c for c in cands if c in owned), cands[0])
    return result


def recipe_self_built(recipe):
    """Package names a rockcraft.yaml unpacks from locally built debs (`dpkg -x debs/<pkg>_*.deb`)."""
    return set(re.findall(r"dpkg -x debs/([A-Za-z0-9.+-]+?)_", Path(recipe).read_text()))


def _glob_regex(pattern):
    out = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def covering_slices(path, sdfs):
    """Return `<pkg>_<slice>` names whose contents entries match `path` (chisel glob semantics)."""
    hits = []
    for pkg, sdf in sdfs.items():
        for name, sl in (sdf.get("slices") or {}).items():
            for entry in (sl.get("contents") or {}):
                if any(_glob_regex(entry.rstrip("/")).match(a) for a in _aliases(path)):
                    hits.append(f"{pkg}_{name}")
                    break
    return hits


def _in_root(root, path):
    return Path(str(root) + path)


def _resolve(root, path, depth=0):
    """Resolve symlinks of a container path inside `root`; return the container path or None."""
    if depth > 40:
        return None
    parts = [p for p in path.split("/") if p]
    cur = ""
    for i, part in enumerate(parts):
        nxt = f"{cur}/{part}"
        host = _in_root(root, nxt)
        if host.is_symlink():
            target = os.readlink(host)
            base = target if target.startswith("/") else f"{cur}/{target}"
            rest = "/".join(parts[i + 1:])
            return _resolve(root, os.path.normpath(base + ("/" + rest if rest else "")), depth + 1)
        if not os.path.lexists(host):
            return None
        cur = nxt
    return cur or "/"


def _is_file_or_link(root, path):
    host = _in_root(root, path)
    return host.is_symlink() or host.is_file()


def _is_elf(host_path):
    try:
        with open(host_path, "rb") as fh:
            return fh.read(4) == b"\x7fELF"
    except OSError:
        return False


def _readelf(host_path):
    out = subprocess.run(["readelf", "-d", "-l", "-W", str(host_path)], capture_output=True, text=True,
                         env={**os.environ, "LC_ALL": "C"}).stdout
    needed = re.findall(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", out)
    runpath = re.findall(r"\((?:RUNPATH|RPATH)\)\s+Library (?:runpath|rpath): \[(.+?)\]", out)
    interp = re.findall(r"Requesting program interpreter: (.+?)\]", out)
    return needed, [d for rp in runpath for d in rp.split(":")], interp


def _extra_lib_dirs(root):
    dirs = []
    conf_dir = _in_root(root, "/etc/ld.so.conf.d")
    if conf_dir.is_dir():
        for conf in sorted(conf_dir.glob("*.conf")):
            for line in conf.read_text(errors="replace").splitlines():
                line = line.split("#", 1)[0].strip()
                if line.startswith("/"):
                    dirs.append(line)
    return dirs


def elf_needed_closure(rootfs, roots, why=None):
    """Libraries (and interpreters) the ELF `roots` need, transitively; `?<soname>` marks a missing one.
    If `why` is a dict, it is filled with {library path: {ELF paths that need it}}."""
    why = {} if why is None else why
    root = Path(rootfs)
    default_dirs = _extra_lib_dirs(root) + DEFAULT_LIB_DIRS
    result, seen, todo = set(), set(), list(roots)
    while todo:
        path = todo.pop()
        real = _resolve(root, path)
        if real is None or real in seen or not _is_elf(_in_root(root, real)):
            continue
        seen.add(real)
        needed, runpath, interp = _readelf(_in_root(root, real))
        origin = os.path.dirname(real)
        search = [d.replace("$ORIGIN", origin).replace("${ORIGIN}", origin) for d in runpath] + default_dirs
        for ip in interp:
            r = _resolve(root, ip)
            for got in ([ip, r] if r else ["?" + os.path.basename(ip)]):
                result.add(got)
                why.setdefault(got, set()).add(real)
            if r:
                todo.append(r)
        for lib in needed:
            hit = None
            for d in ([os.path.dirname(lib)] if "/" in lib else search):
                cand = os.path.normpath(f"{d}/{os.path.basename(lib)}")
                if _resolve(root, cand):
                    hit = cand
                    break
            r = _resolve(root, hit) if hit else None
            for got in ([hit, r] if hit else ["?" + lib]):
                result.add(got)
                why.setdefault(got, set()).add(real)
            if r:
                todo.append(r)
    return result


def _extract(tar_path, dest):
    def keep(member, _path):
        if member.isdev() or member.isfifo() or member.name.startswith("/") or ".." in member.name.split("/"):
            return None
        return member.replace(mode=member.mode | (0o700 if member.isdir() else 0o600), uid=None, gid=None,
                              uname=None, gname=None, deep=False)

    with tarfile.open(tar_path) as tf:
        tf.extractall(dest, filter=keep)


def _rootfs_files(root):
    files = set()
    for dirpath, _dirs, names in os.walk(root):
        for n in names:
            host = os.path.join(dirpath, n)
            files.add("/" + os.path.relpath(host, root))
    return files


def _wheel_files(root, files):
    owned = set()
    for f in files:
        if f.endswith(".dist-info/RECORD"):
            site = os.path.dirname(os.path.dirname(f))
            for line in _in_root(root, f).read_text(errors="replace").splitlines():
                rel = line.split(",", 1)[0]
                if rel:
                    owned.add(os.path.normpath(f"{site}/{rel}"))
    return owned


def _load_sdfs(release, pkgs):
    sdfs = {}
    for pkg in pkgs:
        f = Path(release) / "slices" / f"{pkg}.yaml"
        if f.exists():
            sdfs[pkg] = yaml.safe_load(f.read_text())
    return sdfs


def _recipe_packages(recipe):
    data = yaml.safe_load(Path(recipe).read_text())
    pkgs = set()
    for part in (data.get("parts") or {}).values():
        for item in (part.get("stage-packages") or []) + (part.get("stage-slices") or []):
            pkgs.add(item.split("_", 1)[0])
    return pkgs


def minimise_slices(release, slices):
    """Drop every slice another listed slice already pulls in through (transitive) essential.

    chisel cut installs each slice's essential closure, so the dropped ones still land in the rootfs.
    Order of the kept slices is preserved; slices without an SDF are kept as is.
    """
    essential = {}

    def deps(name):
        if name not in essential:
            sdf = _load_sdfs(release, [name.split("_", 1)[0]]).get(name.split("_", 1)[0]) or {}
            body = (sdf.get("slices") or {}).get(name.split("_", 1)[1], None) or {}
            essential[name] = list(sdf.get("essential") or []) + list(body.get("essential") or [])
        return essential[name]

    wanted = set(slices)
    implied = set()
    for s in slices:
        seen, todo = set(), list(deps(s))
        while todo:
            d = todo.pop()
            if d not in seen:
                seen.add(d)
                todo += deps(d)
        implied |= (seen - {s}) & wanted
    return [s for s in slices if s not in implied]


def _minimise_main(argv):
    ap = argparse.ArgumentParser(prog="analyze.py minimise",
                                 description="print the slice list without slices implied by essential")
    ap.add_argument("--chisel-release", required=True)
    ap.add_argument("slices_file", help="one slice per line; blank lines and # comments ignored")
    args = ap.parse_args(argv)
    lines = Path(args.slices_file).read_text().splitlines()
    slices = [ln.strip() for ln in lines if ln.strip() and not ln.strip().startswith("#")]
    print("\n".join(minimise_slices(args.chisel_release, slices)))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["minimise"]:
        return _minimise_main(argv[1:])
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rootfs", required=True, help="docker export tar, or an extracted directory")
    ap.add_argument("--trace", nargs="*", default=[])
    ap.add_argument("--contents", nargs="+", required=True)
    ap.add_argument("--chisel-release", required=True)
    ap.add_argument("--recipe", help="rockcraft.yaml: diffed against, and its `dpkg -x` debs count as self-built")
    ap.add_argument("--extra-roots", default="",
                    help="comma-separated container paths used only on untraced paths (static review), e.g. /usr/sbin/radvd")
    ap.add_argument("--self-built", default="", help="extra comma-separated self-built package names")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    platforms = dict(kv.split("=") for kv in os.environ.get("ROCKDEPS_PLATFORMS", "dut2=broadcom,vs=vs").split(","))

    with tempfile.TemporaryDirectory(prefix="rockdeps-") as tmp:
        root = Path(args.rootfs)
        if not root.is_dir():
            _extract(args.rootfs, tmp)
            root = Path(tmp)
        files = _rootfs_files(root)

        traced = defaultdict(set)  # path -> platforms
        absent = defaultdict(set)  # traced, but not in this rootfs (failed probe, or differs from the traced build)
        for t in args.trace:
            plat = platforms.get(Path(t).resolve().parts[-3], Path(t).resolve().parts[-3])
            for p in parse_trace(Path(t).read_text(errors="replace").splitlines()):
                src = pyc_source(p)
                if src and _resolve(root, src) is not None:
                    traced[src].add(plat)
                real = _resolve(root, p)
                if real is None:
                    absent[p].add(plat)
                    continue
                traced[p].add(plat)
                traced[real].add(plat)
                for interp in shebang_interpreters(root, real):
                    interp_real = _resolve(root, interp)
                    if interp_real is not None:
                        traced[interp].add(plat)
                        traced[interp_real].add(plat)

        static_roots = {p for p in args.extra_roots.split(",") if p}
        contents = load_contents(args.contents, files | set(traced) | static_roots)
        self_built = {p for p in args.self_built.split(",") if p} | (recipe_self_built(args.recipe) if args.recipe else set())
        owner = attribute(files | set(traced), contents, self_built)
        wheel = _wheel_files(root, files)

        non_archive_elfs = {f for f in files if owner.get(f) is None and _is_elf(_in_root(root, f))}
        traced_elfs = {p for p in traced if _is_elf(_in_root(root, p))}
        why = {}
        closure = elf_needed_closure(root, traced_elfs | non_archive_elfs | static_roots, why)
        missing = sorted(f"{p} (needed by {', '.join(sorted(why.get(p, ())))})" for p in closure if p.startswith("?"))
        closure_owner = attribute({p for p in closure if not p.startswith("?")}, contents, self_built)

        evidence = defaultdict(list)
        plats = defaultdict(set)
        paths_of = defaultdict(set)
        for p, ps in traced.items():
            if owner.get(p):
                evidence[owner[p]].append(f"trace {p}")
                plats[owner[p]] |= ps
                paths_of[owner[p]].add(p)
        for p, pkg in attribute(static_roots, contents, self_built).items():
            if pkg:
                evidence[pkg].append(f"static-root {p}")
                plats[pkg].add("static")
                paths_of[pkg].add(p)
        for p, pkg in closure_owner.items():
            if pkg:
                evidence[pkg].append(f"ELF-needed {p} by {','.join(sorted(why.get(p, ()))[:2])}")
                plats[pkg].add("static")
                paths_of[pkg].add(p)

        sdfs = _load_sdfs(args.chisel_release, evidence)
        lines = [f"# Real dependencies: {args.rootfs}", "",
                 "| package | evidence (count, sample) | platforms | covering slices |", "|---|---|---|---|"]
        for pkg in sorted(evidence):
            sl = sorted({s for p in paths_of[pkg] for s in covering_slices(p, {pkg: sdfs[pkg]})}) if pkg in sdfs \
                else ["NO-SDF"]
            sample = "; ".join(sorted(evidence[pkg])[:3])
            lines.append(f"| {pkg} | {len(evidence[pkg])}: {sample} | {','.join(sorted(plats[pkg]))} | "
                         f"{' '.join(sl) or 'UNCOVERED-PATHS'} |")
        lines += ["", "## Used paths no slice covers (they would be missing from a chiselled rock)", ""]
        for pkg in sorted(p for p in evidence if p in sdfs):
            for path in sorted(paths_of[pkg]):
                if not covering_slices(path, {pkg: sdfs[pkg]}) and _is_file_or_link(root, path):
                    lines.append(f"- `{path}` ({pkg})")
        lines += ["", "## Non-archive files used (self-built debs, wheels, generated)", ""]
        for p in sorted(p for p in traced if owner.get(p) is None):
            lines.append(f"- `{p}` {'(wheel)' if p in wheel else ''} [{','.join(sorted(traced[p]))}]")
        lines += ["", "## Traced but absent from this rootfs (failed probes, or build differences: review)", ""]
        lines += [f"- `{p}` [{','.join(sorted(ps))}]" for p, ps in sorted(absent.items())]
        lines += ["", "## Missing libraries (NEEDED but not found in rootfs)", ""] + [f"- `{m}`" for m in missing]
        if args.recipe:
            current = _recipe_packages(args.recipe)
            lines += ["", f"## Diff against {args.recipe}", "",
                      "Unused (in recipe, no evidence): " + ", ".join(sorted(current - set(evidence))),
                      "", "Used but not in recipe (came in as Depends): " + ", ".join(sorted(set(evidence) - current))]
        Path(args.out).write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
