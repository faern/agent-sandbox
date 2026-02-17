# claude-sandbox

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside a rootless podman container.
Isolates Claude from your system — it can only access the current working directory. Currently only
designed for being used on a Linux host.

The sandbox gets a user with the same username and home dir as on your host. The container
then runs with `--userns=keep-id` so file ownership matches the host. The intention is that all
file paths inside the container should match the host. This makes all absolute and relative paths
written to files match inside and outside the sandbox for a smoother experience.

This claude sandbox wrapper is not an AI agent session manager or git worktree manager. Nor does
it come bundled with skills or anything else that will get old in a week.
All it does is help you isolate claude in a container to prevent it from accessing most of your
host system, or messing up files outside our project working directory.

`claude-sandbox` does not come with any prebuilt container images. Instead this script builds
an image on demand when executed. The default container definition is very minimil,
so it is fast to build. The container definition is configurable both globally and per
project (working directory).


## Claude version

By default it mounts your host's claude binary into the container. This both makes the container
image smaller and allows you to automatically get updates without rebuilding the image. However,
this is configurable. If you want claude installed into the image because you do not have it on the
host, or you prefer it that way, you can get that with `--claude install`. This installs claude
at the very end of the image build (after all containerfile and sandbox setup), as the sandbox user.
And if you define your own custom containerfile where you install claude yourself,
then you can tell claude-sandbox to neither mount nor install claude in the container with
`--claude none`.

## Claude login credentials and configs

For simplicity, the sandbox gets a **copy** of your ~/.claude and ~/.claude.json mounted into
it. This allows claude in the sandbox to be directly logged in and have all your own skills, rules,
MCPs etc. Depending on your threat model this can of course be a risk.

## Requirements

- [Podman](https://podman.io/) (rootless)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on the host (unless using `--claude install` or `--claude none`)
- `fzf` (only for `--cleanup`)

## Install

This is just a standalone bash script. Copy it somewhere in your PATH

```sh
cp claude-sandbox ~/.local/bin/
```

## Usage

```sh
# Starts claude in the sandbox, with the current working directory read-write
# mounted in the container.
claude-sandbox

# Read-only project mount
claude-sandbox --read-only

# No project mount at all — pure chat
claude-sandbox --stateless

# Force image rebuild
claude-sandbox --rebuild

# Pass args to claude after a double dash (--)
claude-sandbox -- --model sonnet -p "explain this repo"

# Add Linux capabilities
claude-sandbox --cap-add NET_RAW

# List and remove old images. claude-sandbox has no automatic cleanup yet.
claude-sandbox --cleanup

# Install claude into the image during build
claude-sandbox --claude install

# Skip host binary mount (use when containerfile installs claude)
claude-sandbox --claude none

# Verbose output from the sandbox setup
claude-sandbox -v
```

## Custom containers

Place a `.claude-sandbox.containerfile` in your project root (or globally in
`~/.config/claude-sandbox/`). Project containerfiles override the global one.

Project configs require trust approval on first use and after any change. This protects
it from being poisoned by the container, since it is available with write permissions
inside the sandbox. Might want to improve here to make it invisible or read-only
to the sandbox.

The file **must** include a `FROM` line. claude-sandbox splits your file at the
first `FROM` line and injects its own instructions into the final Containerfile.
The resulting build order is:

```
─── Your FROM line ───────────────────────────────────────────
INJECTED: ARG USERNAME, USER_HOME, USER_UID, USER_GID
INJECTED: User creation (matching host UID/GID)
─── Rest of your containerfile ───────────────────────────────
INJECTED: USER root (reset after your containerfile)
INJECTED: Sudo setup (if sudo is installed)
INJECTED: USER ${USERNAME}, mkdir, PATH setup
INJECTED: Claude install (only with --claude install)
```

Since the sandbox user and ARGs are injected before the rest of your file, you
can freely use `USER ${USERNAME}` to run commands as the sandbox user, then switch
back with `USER root` as needed.

The following `ARG`s are available directly in your containerfile (no need to
declare them):

- `USERNAME` — host username
- `USER_HOME` — host home directory path
- `USER_UID` — host user ID
- `USER_GID` — host group ID

Images are tagged by config content hash — different configs produce separate images
that rebuild automatically when the config changes.

### Example: Fedora + Rust

`.claude-sandbox.containerfile`:
```dockerfile
FROM fedora:latest

RUN dnf install -y git curl ripgrep fd-find jq gcc sudo \
    && dnf clean all

# Install Rust as the sandbox user — no chown needed
USER ${USERNAME}
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain stable --component rust-analyzer
ENV PATH="${USER_HOME}/.cargo/bin:${PATH}"
```

### Example: Ubuntu + Node.js

`.claude-sandbox.containerfile`:
```dockerfile
FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git curl ca-certificates ripgrep fd-find jq build-essential sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
```

## Environment variables

- `ANTHROPIC_*` — all `ANTHROPIC_` prefixed env vars are forwarded into the container
- `SANDBOX_CONTAINERFILE` — override containerfile path (must exist, skips discovery)

## License

This project is licensed under the [GNU General Public License v3.0 or later](LICENSE).
