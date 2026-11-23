#!/usr/bin/env python3
"""Render job.yaml.in into a Testflinger job file on stdout."""
import argparse
import re
import string
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent / "job.yaml.in"


def render(sha12, gh_run, repo, artifact_id, artifact_digest, scope, secret):
    checks = [(re.fullmatch(r"[0-9a-f]{12}", sha12), "sha12"), (re.fullmatch(r"\d+", gh_run), "gh-run"),
              (re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo), "repo"),
              (re.fullmatch(r"\d+", artifact_id), "artifact-id"),
              (re.fullmatch(r"sha256:[0-9a-f]{64}", artifact_digest), "artifact-digest"),
              (scope in ("full", "smoke"), "scope"), (re.fullmatch(r"[A-Za-z0-9_./-]+", secret), "secret")]
    for ok, name in checks:
        if not ok:
            raise ValueError("invalid --%s" % name)
    return string.Template(TEMPLATE.read_text()).substitute(
        SHA12=sha12, GH_RUN=gh_run, REPO=repo, ARTIFACT_ID=artifact_id, ARTIFACT_DIGEST=artifact_digest,
        SCOPE=scope, SECRET=secret)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ("--sha12", "--gh-run", "--repo", "--artifact-id", "--artifact-digest", "--scope", "--secret"):
        parser.add_argument(opt, required=True)
    a = parser.parse_args(argv)
    sys.stdout.write(render(a.sha12, a.gh_run, a.repo, a.artifact_id, a.artifact_digest, a.scope, a.secret))


if __name__ == "__main__":
    main()
