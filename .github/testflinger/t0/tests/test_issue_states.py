import json
import threading
import urllib.error
import urllib.request
from urllib.parse import urlencode

import pytest

import issue_states

CONDITIONS = """
a/test_a.py:
  skip:
    reason: "see https://github.com/sonic-net/sonic-mgmt/issues/1 for details"
    conditions:
      - "https://github.com/sonic-net/sonic-mgmt/issues/1 and asic_type in ['vs']"
      - "(https://github.com/sonic-net/sonic-buildimage/issues/2)"
b/test_b.py::test_x:
  xfail:
    conditions_logical_operator: or
    conditions: https://github.com/sonic-net/sonic-swss/issues/3
c/test_c.py:
  skip:
    conditions:
      - "https://jira.example.com/browse/X-4"
      - "topo_type in ['t1']"
"""


def test_urls_come_only_from_conditions_and_only_github(tmp_path):
    import yaml
    assert issue_states.condition_urls(yaml.safe_load(CONDITIONS)) == {
        "https://github.com/sonic-net/sonic-mgmt/issues/1",
        "https://github.com/sonic-net/sonic-buildimage/issues/2",
        "https://github.com/sonic-net/sonic-swss/issues/3",
    }


def test_snapshot_keys_by_api_url_and_drops_failures(tmp_path):
    f = tmp_path / "tests_mark_conditions.yaml"
    f.write_text(CONDITIONS)
    seen = []

    def get(url, token):
        seen.append((url, token))
        if url.endswith("/issues/3"):
            raise OSError("boom")
        return {"state": "closed", "labels": []}

    urls, states = issue_states.snapshot([f], "tok", get)
    assert len(urls) == 3
    assert sorted(u for u, _ in seen) == sorted([
        "https://api.github.com/repos/sonic-net/sonic-mgmt/issues/1",
        "https://api.github.com/repos/sonic-net/sonic-buildimage/issues/2",
        "https://api.github.com/repos/sonic-net/sonic-swss/issues/3"])
    assert all(t == "tok" for _, t in seen)
    assert set(states) == {"https://api.github.com/repos/sonic-net/sonic-mgmt/issues/1",
                           "https://api.github.com/repos/sonic-net/sonic-buildimage/issues/2"}


@pytest.fixture
def proxy():
    states = {"https://api.github.com/repos/sonic-net/sonic-mgmt/issues/1":
              {"state": "closed", "labels": [{"name": "Duplicate"}]}}
    srv = issue_states.server(states, "127.0.0.1", 0)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield "http://127.0.0.1:%d" % srv.server_address[1]
    srv.shutdown()


def ask(base, url):
    # The request conditional_mark/issue.py sends to SONIC_AUTOMATION_PROXY_GITHUB_ISSUES_URL.
    return urllib.request.urlopen("%s/?%s" % (base.rstrip("/"), urlencode({"github_issue_url": url})), timeout=5)


def test_serve_answers_a_known_issue(proxy):
    data = json.load(ask(proxy, "https://api.github.com/repos/sonic-net/sonic-mgmt/issues/1"))
    assert data == {"state": "closed", "labels": [{"name": "Duplicate"}]}


def test_serve_gives_404_for_an_unknown_issue(proxy):
    with pytest.raises(urllib.error.HTTPError) as err:
        ask(proxy, "https://api.github.com/repos/sonic-net/sonic-mgmt/issues/9")
    assert err.value.code == 404
