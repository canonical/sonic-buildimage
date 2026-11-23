import subprocess

import pytest
import yaml

import render_job

ARGS = dict(sha12="0123456789ab", gh_run="42", repo="canonical/sonic-buildimage", artifact_id="14400660343",
            artifact_digest="sha256:" + "a" * 64, scope="smoke", secret="sonic-buildimage/run-42-1")


def test_render_gives_a_valid_job():
    job = yaml.safe_load(render_job.render(**ARGS))
    assert job["job_queue"] == "sonic-ci"
    assert job["global_timeout"] == 43200 and job["output_timeout"] == 7200
    assert job["provision_data"] == {"distro": "resolute"}
    assert job["test_data"]["secrets"] == {"GH_TOKEN": "sonic-buildimage/run-42-1"}
    assert job["test_data"]["attachments"] == [{"local": "t0-harness.tar.gz"}]
    assert "sha:0123456789ab" in job["tags"] and "gh-run:42" in job["tags"]
    cmds = job["test_data"]["test_cmds"]
    for part in ("SCOPE='smoke'", "REPO='canonical/sonic-buildimage'", "ARTIFACT_ID='14400660343'",
                 "ARTIFACT_DIGEST='sha256:" + "a" * 64 + "'"):
        assert part in cmds
    subprocess.run(["bash", "-n"], input=cmds, text=True, check=True)


@pytest.mark.parametrize("field,value", [("scope", "all"), ("sha12", "XYZ"), ("gh_run", "12a"),
                                         ("repo", "canonical"), ("repo", "a/b c"), ("artifact_id", "x1"),
                                         ("artifact_digest", "f" * 64), ("artifact_digest", "sha256:abc"),
                                         ("secret", "a b"), ("secret", "x'y")])
def test_render_rejects_bad_values(field, value):
    with pytest.raises(ValueError):
        render_job.render(**dict(ARGS, **{field: value}))
