"""scripts/deploy.sh against the fake AWS CLI in tests/fakes."""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAKES = ROOT / "tests" / "fakes"


def deploy(tmp_path, *args):
    log = tmp_path / "aws.jsonl"
    env = {"PATH": f"{FAKES}:{os.environ['PATH']}", "HOME": str(tmp_path), "FAKE_AWS_LOG": str(log)}
    proc = subprocess.run([str(ROOT / "scripts" / "deploy.sh"), *args], env=env,
                          capture_output=True, text=True)
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    return proc, calls


def test_home_region_first_and_named_iam(tmp_path):
    proc, calls = deploy(tmp_path, "--regions", "us-west-2,us-east-1", "--profile", "dev",
                         "--param", "EnableDefaultHostManagement=true")
    assert proc.returncode == 0, proc.stderr
    deploys = [c for c in calls if "deploy" in c]
    assert [c[c.index("--region") + 1] for c in deploys] == ["us-west-2", "us-east-1"]
    for call in deploys:
        assert call[:2] == ["--profile", "dev"]
        assert "CAPABILITY_NAMED_IAM" in call
        overrides = call[call.index("--parameter-overrides") + 1:]
        assert overrides == ["HomeRegion=us-west-2", "EnableDefaultHostManagement=true"]


def test_requires_regions(tmp_path):
    proc, calls = deploy(tmp_path)
    assert proc.returncode == 2 and calls == []
