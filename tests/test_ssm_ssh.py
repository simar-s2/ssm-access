"""bin/ssm-ssh against a fake AWS CLI. The real ssh-keygen makes the key."""

import json
import os
import stat
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SSM_SSH = ROOT / "bin" / "ssm-ssh"
FAKES = ROOT / "tests" / "fakes"


@pytest.fixture
def run(tmp_path):
    def _run(*args, instances=None, plugin=True):
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir(exist_ok=True)
        if not (bin_dir / "aws").exists():
            os.symlink(FAKES / "aws", bin_dir / "aws")
        plugin_link = bin_dir / "session-manager-plugin"
        if plugin and not plugin_link.exists():
            os.symlink(FAKES / "session-manager-plugin", plugin_link)
        log = tmp_path / "aws.jsonl"
        log.unlink(missing_ok=True)
        env = {
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "HOME": str(tmp_path),
            "FAKE_AWS_LOG": str(log),
            "FAKE_INSTANCES": json.dumps(instances or {}),
        }
        proc = subprocess.run([str(SSM_SSH), *args], env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return proc, calls
    return _run


def test_config_block(run, tmp_path):
    proc, calls = run("config", "dev-box", "i-0a1b2c3d4e5f60001", "--user", "ubuntu",
                      "--profile", "dev", "--region", "eu-west-1")
    assert proc.returncode == 0, proc.stderr
    lines = [line.strip() for line in proc.stdout.splitlines()]
    assert lines[0] == "Host dev-box"
    assert "HostName i-0a1b2c3d4e5f60001" in lines
    assert "User ubuntu" in lines
    assert f"IdentityFile {tmp_path}/.ssh/ssm-ssh/id_ed25519" in lines
    assert f"ProxyCommand {SSM_SSH} proxy %h %p %r --profile dev --region eu-west-1" in lines
    assert calls == []


def test_key_is_created_once_and_private(run, tmp_path):
    run("config", "a", "i-0a1b2c3d4e5f60001")
    key = tmp_path / ".ssh" / "ssm-ssh" / "id_ed25519"
    first = key.read_text()
    assert stat.S_IMODE(key.stat().st_mode) == 0o600
    assert stat.S_IMODE(key.parent.stat().st_mode) == 0o700
    run("config", "b", "i-0a1b2c3d4e5f60002")
    assert key.read_text() == first


def test_proxy_pushes_the_key_then_opens_the_tunnel(run, tmp_path):
    proc, calls = run("proxy", "i-0a1b2c3d4e5f60001", "22", "ec2-user", "--profile", "dev")
    assert proc.returncode == 0, proc.stderr
    push, tunnel = calls
    assert push[:4] == ["--profile", "dev", "ec2-instance-connect", "send-ssh-public-key"]
    assert push[push.index("--instance-os-user") + 1] == "ec2-user"
    assert push[push.index("--ssh-public-key") + 1] == f"file://{tmp_path}/.ssh/ssm-ssh/id_ed25519.pub"
    assert tunnel[2:4] == ["ssm", "start-session"]
    assert tunnel[tunnel.index("--document-name") + 1] == "AWS-StartSSHSession"
    assert tunnel[tunnel.index("--parameters") + 1] == "portNumber=22"


def test_proxy_resolves_a_name_tag(run):
    proc, calls = run("proxy", "jump-host", "22", "ec2-user",
                      instances={"jump-host": ["i-0a1b2c3d4e5f60009"]})
    assert proc.returncode == 0, proc.stderr
    assert "describe-instances" in calls[0]
    assert "Name=instance-state-name,Values=running" in calls[0]
    assert calls[1][calls[1].index("--instance-id") + 1] == "i-0a1b2c3d4e5f60009"


@pytest.mark.parametrize("instances, message", [
    ({}, "no running instance named 'jump-host'"),
    ({"jump-host": ["i-0a1b2c3d4e5f60001", "i-0a1b2c3d4e5f60002"]}, "several running instances"),
])
def test_ambiguous_or_missing_names_fail(run, instances, message):
    proc, calls = run("proxy", "jump-host", "22", "ec2-user", instances=instances)
    assert proc.returncode != 0
    assert message in proc.stderr
    assert not any("start-session" in c for c in calls)


def test_missing_plugin_is_explained(run):
    proc, calls = run("proxy", "i-0a1b2c3d4e5f60001", "22", "ec2-user", plugin=False)
    assert proc.returncode != 0
    assert "Session Manager plugin is not installed" in proc.stderr
    assert calls == []


def test_usage_errors(run):
    assert run()[0].returncode == 2
    assert run("config", "only-a-name")[0].returncode == 2
    assert run("--help")[0].returncode == 0
