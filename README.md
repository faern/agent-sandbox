# agent-sandbox

Run AI coding agents inside rootless podman containers.
Supports [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and
[OpenCode](https://opencode.ai/). Isolates the agent from your system — it can only
access the current working directory. Currently only designed for being used on a Linux host.

The sandbox gets a user with the same username and home dir as on your host. The container
then runs with `--userns=keep-id` so file ownership matches the host. The intention is that all
file paths inside the container should match the host. This makes all absolute and relative paths
written to files match inside and outside the sandbox for a smoother experience.

This is not an AI agent session manager or git worktree manager. Nor does
it come bundled with skills or anything else that will get old in a week.
All it does is help you isolate the agent in a container to prevent it from accessing most of your
host system, or messing up files outside your project working directory.

`agent-sandbox` does not come with any prebuilt container images. Instead the script builds
an image on demand when executed. The default container definition is very minimal,
so it is fast to build. The container definition is configurable both globally and per
project (working directory).

## How it works

`agent-sandbox` is a single script. It is invoked via symlinks named `claude-sandbox` and
`opencode-sandbox`. The script detects which agent to use based on the name it was invoked as.
Each agent gets its own containerfile name, config paths, environment variables, and install method.

## Agent binary

By default the host's agent binary is bind-mounted into the container. This keeps the container
image small and lets you get updates without rebuilding. This is configurable with `--agent`:

- `--agent host` (default) — Mount the host binary read-only. If the binary is not found
  on the host, falls back to `install` automatically.
- `--agent install` — Install the agent into the container image during build
  (runs the agent's official install script as the sandbox user).
- `--agent none` — Don't provide the agent at all. Use this when your custom
  containerfile installs it.

## Login credentials and configs

For simplicity, the sandbox gets a **copy** of your agent's config files mounted into it.

| Agent | Configs copied |
|-------|---------------|
| Claude Code | `~/.claude.json`, `~/.claude/` |
| OpenCode | `$XDG_CONFIG_HOME/opencode/`, `~/.local/share/opencode/` |

This allows the agent in the sandbox to be directly logged in and have all your settings.
Depending on your threat model this can of course be a risk.

## Requirements

- [Podman](https://podman.io/) (rootless)
- The agent installed on the host (unless using `--agent install` or `--agent none`)
- `fzf` (only for `--cleanup`)

## Install

This is just a standalone bash script. Copy or symlink it somewhere in your PATH.

```sh
cp agent-sandbox ~/.local/bin/
ln -s agent-sandbox ~/.local/bin/claude-sandbox
ln -s agent-sandbox ~/.local/bin/opencode-sandbox
```

## Usage

Invoke as `claude-sandbox` or `opencode-sandbox`. All examples below use `claude-sandbox`
but `opencode-sandbox` works identically.

```sh
# Start the agent in the sandbox, with the current working directory
# read-write mounted in the container
claude-sandbox

# Read-only project mount
claude-sandbox --read-only

# No project mount at all — pure chat
claude-sandbox --stateless

# Force image rebuild
claude-sandbox --rebuild

# Drop into a shell inside the sandbox instead of starting the agent directly
claude-sandbox --shell

# Pass args to the agent after a double dash (--)
claude-sandbox -- --model sonnet -p "explain this repo"

# Add Linux capabilities
claude-sandbox --cap-add NET_RAW

# List and remove old images
claude-sandbox --cleanup

# Install the agent into the image during build
claude-sandbox --agent install

# Skip host binary mount (use when containerfile installs the agent)
claude-sandbox --agent none

# Pass --dangerously-skip-permissions to Claude Code (bypasses permission checks)
claude-sandbox --yolo

# Verbose output from the sandbox setup
claude-sandbox -v
```

## Custom containers

Place a `Containerfile.agent` in your project root, or globally in
`$XDG_CONFIG_HOME/agent-sandbox/` (defaults to `~/.config/agent-sandbox/`).
Project containerfiles override the global one.

Project configs require trust approval on first use and after any change. This protects
it from being poisoned by the container, since it is available with write permissions
inside the sandbox.

The file **must** include a `FROM` line. The script splits your file at the
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
INJECTED: Agent install (only with --agent install)
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

`Containerfile.agent`:
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

`Containerfile.agent`:
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

| Agent | Forwarded env vars |
|-------|-------------------|
| Claude Code | `ANTHROPIC_*` |
| OpenCode | `ANTHROPIC_*`, `OPENAI_*`, `GEMINI_*`, `GROQ_*`, `AWS_*`, `AZURE_*`, `OPENCODE_*`, `GOOGLE_*`, `GITLAB_*`, `CLOUDFLARE_*`, `GITHUB_TOKEN` |

- `SANDBOX_CONTAINERFILE` — override containerfile path (must exist, skips discovery)

## License

This project is licensed under the [GNU General Public License v3.0 or later](LICENSE).
