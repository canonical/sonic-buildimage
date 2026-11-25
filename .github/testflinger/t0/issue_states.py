#!/usr/bin/env python3
"""Snapshot the GitHub issues that sonic-mgmt's mark conditions name, and serve them as its issue proxy.

snapshot: on the runner, with GH_TOKEN; serve: on the machine, for SONIC_AUTOMATION_PROXY_GITHUB_ISSUES_URL.
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# The same pattern and URL rewrite as tests/common/plugins/conditional_mark (__init__.py, issue.py).
URL_RE = re.compile(r"https?://[^ )]+")


def api_url(url):
    return url.replace("github.com", "api.github.com/repos")


def condition_urls(data):
    found = set()
    if isinstance(data, dict):
        for key, value in data.items():
            if key == "conditions":
                for cond in value if isinstance(value, list) else [value]:
                    if isinstance(cond, str):
                        found.update(u for u in URL_RE.findall(cond) if "github" in u.split("/")[2].lower())
            else:
                found |= condition_urls(value)
    elif isinstance(data, list):
        for item in data:
            found |= condition_urls(item)
    return found


def fetch(url, token):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token,
                                               "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        issue = json.load(resp)
    return {"state": issue["state"], "labels": [{"name": label["name"]} for label in issue.get("labels", [])]}


def snapshot(files, token, get=fetch):
    import yaml
    urls = set()
    for f in files:
        urls |= condition_urls(yaml.safe_load(Path(f).read_text()))
    states = {}

    def one(url):
        try:
            return url, get(api_url(url), token)
        except Exception as err:
            print("::warning::%s: %s" % (url, err), file=sys.stderr)
            return url, None

    with ThreadPoolExecutor(8) as pool:
        for url, state in pool.map(one, sorted(urls)):
            if state is not None:
                states[api_url(url)] = state
    return urls, states


class Handler(BaseHTTPRequestHandler):
    states = {}

    def do_GET(self):
        url = parse_qs(urlparse(self.path).query).get("github_issue_url", [""])[0]
        state = self.states.get(url)
        body = json.dumps(state).encode() if state else b"{}"
        self.send_response(200 if state else 404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def server(states, host, port):
    handler = type("SnapshotHandler", (Handler,), {"states": states})
    return ThreadingHTTPServer((host, port), handler)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot")
    s.add_argument("--out", required=True)
    s.add_argument("files", nargs="+")
    v = sub.add_parser("serve")
    v.add_argument("--states", required=True)
    v.add_argument("--host", required=True)
    v.add_argument("--port", type=int, required=True)
    a = p.parse_args()
    if a.cmd == "snapshot":
        urls, states = snapshot(a.files, os.environ["GH_TOKEN"])
        Path(a.out).write_text(json.dumps(states, indent=1, sort_keys=True))
        print("%d of %d issues" % (len(states), len(urls)))
        return 0 if len(states) == len(urls) else 1
    server(json.loads(Path(a.states).read_text()), a.host, a.port).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
