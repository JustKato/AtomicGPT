# Setup and CLI usage

[Back to the README](../README.md) · [Configuration](configuration.md) · [Updates and logs](updates-and-logs.md)

## Requirements

Run AtomicGPT as your normal user on Linux. The default RPM is for x86_64;
AtomicGPT checks the package name and architecture before installing it.
You don't need `sudo` or a reboot to run these scripts.

The installer needs:

- Bash 4.3 or later.
- `rpm` with Lua `rpm.vercmp` support, `rpm2cpio`, and GNU `cpio`.
- `curl` 7.68 or later for downloads and conditional requests.
- `realpath`, `mktemp`, `flock`, `find`, `sort`, `readlink`, `head`, `cat`, `cp`,
  `mv`, `rm`, `mkdir`, `rmdir`, `chmod`, `uname`, `sleep`, `date`, and `tee`.

The scheduling wizard also needs `systemctl` and a working systemd user session.
Python 3 and ShellCheck are development tools, not installer dependencies.

Desktop integration uses `notify-send`, `xdg-mime`, `update-desktop-database`,
and `kbuildsycoca6` when available. Without a notification tool, warnings still
appear in the terminal or scheduler journal.

Extraction leaves system dependencies to your desktop. AtomicGPT doesn't run
RPM installation scripts or put system libraries, AppArmor policies, or
repository configuration into the host. It doesn't disable ChatGPT's sandbox.

## Setup wizard

```bash
./setup-wizard.sh
```

The wizard explains the install location, downloads, desktop integration,
closing behavior, warning delay, and backups. It asks you to review the choices
before saving `.env`, then offers to open the auto-update wizard.

It uses existing settings as defaults and backs up an existing `.env` before
replacing it. The saved file and backup have private permissions. Cancelling
before save leaves the old file in place; the wizard doesn't install ChatGPT.

For plain output, use `--no-color` or set `NO_COLOR`. The interface also uses
plain output when you redirect it. To save another configuration:

```bash
./setup-wizard.sh --output /absolute/path/to/update.env
./install-chatgpt.sh --config /absolute/path/to/update.env
```

## Common commands

```bash
# Latest package into another folder:
./install-chatgpt.sh --latest --target "$HOME/Programs/ChatGPT"

# A local RPM or a trusted HTTPS URL:
./install-chatgpt.sh --rpm ./chatgpt.x86_64.rpm
./install-chatgpt.sh --rpm https://example.com/chatgpt.x86_64.rpm

# Compare versions without installing or closing ChatGPT:
./install-chatgpt.sh --check

# Keep the previous application folder:
./install-chatgpt.sh --keep-backup

# Install files without desktop integration:
./install-chatgpt.sh --no-integrate

# Unattended updates while ChatGPT is closed:
./install-chatgpt.sh --non-interactive --if-running skip

# Allow an unattended update to warn and close ChatGPT:
./install-chatgpt.sh --non-interactive --yes --close-delay 10

./install-chatgpt.sh --help
./install-chatgpt.sh --version
```

Value options accept `--name=value` as well as `--name value`.
`--install-dir` is an alias for `--target`.

## Desktop integration

AtomicGPT creates `~/.local/bin/chatgpt` and a desktop entry under
`${XDG_DATA_HOME:-$HOME/.local/share}/applications`. It registers `codex://`
links when `xdg-mime` is available. An existing regular file at the command
path stays in place.

If the shell can't find `chatgpt`, add the command directory to your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

For `.env` settings and precedence, read [configuration](configuration.md).
For version comparisons, closing ChatGPT, backups, and exit codes, read
[updates and logs](updates-and-logs.md). To schedule checks or remove them, read
[automatic updates](automatic-updates.md).
