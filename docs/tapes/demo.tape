# Render with: vhs docs/tapes/demo.tape (from the repository root)
Output docs/images/demo.gif
Set Shell "bash"
Set FontSize 16
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms
Set Width 1300
Set Height 520
Env BASH_SILENCE_DEPRECATION_WARNING "1"

# Same setup as scripts/demo.sh: a scratch HOME and the fake AWS CLI.
Hide
Type 'export REPO=$PWD HOME=$(mktemp -d) FAKE_AWS_LOG=/dev/null; mkdir -p $HOME/.local/bin $HOME/.ssh; install -m 755 bin/ssm-ssh $HOME/.local/bin/; export PATH=$HOME/.local/bin:$REPO/tests/fakes:$PATH' Enter
Type 'export PS1="\[\e[1;35m\]ssm-access\[\e[0m\] $ "; clear' Enter
Sleep 500ms
Show
Type "ssm-ssh config dev-box i-0a1b2c3d4e5f60001 --profile dev | tee -a ~/.ssh/config" Sleep 400ms Enter
Sleep 2s
Type "ssh -G -F ~/.ssh/config dev-box | grep -E '^(hostname|user|proxycommand) '" Sleep 400ms Enter
Sleep 2s
Type "terraform test" Sleep 400ms Enter
Wait+Screen@120s /passed, 0 failed/
Sleep 5s
