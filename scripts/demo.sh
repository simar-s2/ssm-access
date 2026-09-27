#!/usr/bin/env bash
# What the README recording shows, reproducible without an AWS account: runs in
# a scratch HOME (so your ~/.ssh is untouched) against the fake AWS CLI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOME=$(mktemp -d)
export HOME PATH="$HOME/.local/bin:$ROOT/tests/fakes:$PATH" FAKE_AWS_LOG=/dev/null
mkdir -p "$HOME/.local/bin" "$HOME/.ssh"
install -m 755 "$ROOT/bin/ssm-ssh" "$HOME/.local/bin/ssm-ssh"

set -x
ssm-ssh config dev-box i-0a1b2c3d4e5f60001 --profile dev | tee -a ~/.ssh/config
ssh -G -F ~/.ssh/config dev-box 2>/dev/null | grep -E '^(hostname|user|proxycommand) '
