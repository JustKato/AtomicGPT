# ChatGPT RPM installer for atomic desktops

Install and update ChatGPT in a folder such as `~/Programs/ChatGPT`, without
installing the RPM into the host operating system. This is useful on atomic
desktops where you would otherwise extract each RPM by hand and run its binaries.

The installer downloads the latest package or reads a local RPM, compares its
version with the installed version, and replaces the application only when the
package is newer. A guided terminal wizard creates your `.env` configuration;
a separate wizard sets up automatic checks with a **systemd user timer** and
can remove them completely. Installation and update attempts are recorded in
the project's `logs/` directory.

This is a community installer. The default package comes from OpenAI's download
server; this project does not build or redistribute ChatGPT.

## Requirements

Run as your normal user on Linux. No `sudo`, host RPM installation, or reboot is
required by these scripts.

- Bash 4.3 or later.
- `rpm` with Lua `rpm.vercmp` support, `rpm2cpio`, and GNU `cpio`.
- Standard utilities: `realpath`, `mktemp`, `flock`, `find`, `sort`, `readlink`,
  `head`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `chmod`, `uname`, `sleep`,
  `date`, and `tee`.
- `curl` 7.68 or later for downloads and conditional HTTP requests.
- `systemctl` and an active systemd user session for the automatic-update wizard.

`notify-send`, `xdg-mime`, `update-desktop-database`, and `kbuildsycoca6` are
optional. They provide desktop warnings, URI registration, and launcher refresh.
Warnings always appear in the terminal or scheduler log even without desktop
notifications.

The default RPM is for **x86_64**. Package name and architecture are checked before
installation. Extraction does not install system libraries, RPM scripts,
AppArmor policies, or repository configuration into the host. Your desktop must
already provide the runtime libraries and sandbox support needed by ChatGPT.
These scripts do not disable the application's sandbox.

## Quick start

Keep this project in a permanent directory; retain the `lib/` folder alongside
the entry scripts.

```bash
./setup-wizard.sh
./install-chatgpt.sh
```

The setup wizard explains each setting and guides you through the installation
folder, automatic downloads on future runs, desktop integration, handling a
running ChatGPT, warning delay, and backups. It shows a summary before saving
and offers to open the automatic-update wizard at the end. Downloading on each
run and scheduling background checks are separate choices.

Existing `.env` settings are used as defaults. Saving over an existing file
creates a private `.env.backup.<timestamp>.<suffix>` first. Cancelling or pressing
Ctrl+C before save leaves the existing file unchanged. The wizard itself
does not download or install ChatGPT.

The terminal interface requires no extra packages and falls back to plain
text when output is redirected. Use `--no-color` or `NO_COLOR` to disable colors
and screen clearing, or save another configuration with:

```bash
./setup-wizard.sh --output /absolute/path/to/update.env
./install-chatgpt.sh --config /absolute/path/to/update.env
```

For manual configuration, copy `.env.example` to `.env` and edit it instead.

The default target is `~/Programs/ChatGPT`. Launch it with:

```bash
~/Programs/ChatGPT/usr/bin/chatgpt
```

By default the installer also creates `~/.local/bin/chatgpt`, a ChatGPT desktop
entry, and a `codex://` URI handler. Desktop entries use
`${XDG_DATA_HOME:-$HOME/.local/share}/applications`. An existing regular file at
`~/.local/bin/chatgpt` is preserved. Add `~/.local/bin` to your shell's `PATH` if
needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Configuration and CLI

The project `.env` is read automatically, regardless of the working directory.
Precedence is **built-in defaults → `.env` → exported environment → CLI options**.
Use `--config /absolute/path/to/update.env` for another file, or `--no-config`
to ignore the project `.env`.

For local packages, configure:

```dotenv
INSTALL_DIR="${HOME}/Programs/ChatGPT"
DOWNLOAD_LATEST=false
RPM_PATH="/home/yourname/Downloads/chatgpt.x86_64.rpm"
```

Set `DOWNLOAD_LATEST=true` to fetch the package at `RPM_URL` instead. `RPM_PATH`
is ignored in that mode. A relative `RPM_PATH` in a config file resolves beside
that file; a relative CLI `--rpm` path resolves from the current directory.
Use an absolute install location, or a home-relative path.

The `.env` parser accepts literal `KEY=value`, optional surrounding single or
double quotes, blank lines, and full-line comments. A leading `~`, `$HOME`, or
`${HOME}` is expanded in paths. It does not execute shell code, expand other
variables, accept `export` declarations, or support inline comments. Booleans
must be `true` or `false`; unknown settings are rejected. See `.env.example`
for every setting.

Common commands:

```bash
# Latest package into a custom directory:
./install-chatgpt.sh --latest --target "$HOME/Programs/ChatGPT"

# A local RPM, or a specific trusted HTTPS URL:
./install-chatgpt.sh --rpm ./chatgpt.x86_64.rpm
./install-chatgpt.sh --rpm https://example.com/chatgpt.x86_64.rpm

# Compare versions without replacing files or closing ChatGPT:
./install-chatgpt.sh --check

# Retain the previous application folder:
./install-chatgpt.sh --keep-backup

# Skip desktop integration:
./install-chatgpt.sh --no-integrate

# Unattended updates that wait until ChatGPT is closed:
./install-chatgpt.sh --non-interactive --if-running skip

# Unattended updates allowed to warn and close ChatGPT:
./install-chatgpt.sh --non-interactive --yes --close-delay 10

./install-chatgpt.sh --help
```

Value options also accept `--name=value`. `--force` explicitly permits
reinstallation, downgrades, or replacement of an untracked directory.

## Update behavior and existing manual installations

The installer records the installed RPM epoch, version, and release in
`.chatgpt-install-info` inside the application folder. Comparison uses RPM's
own ordering, including packaging revisions and prerelease versions. Equal or
older packages leave the installation and running application untouched.
[RPM's version documentation](https://rpm.org/docs/6.0.x/man/rpm-version.7)
explains these rules.

A folder extracted manually, or created by the old installer, has no version
record. The installer cannot reliably determine its original RPM version and
does not launch the GUI to guess it. Adopt it once with:

```bash
./install-chatgpt.sh --target "$HOME/Programs/ChatGPT" --force --keep-backup
```

Use a target containing only ChatGPT: its contents are replaced as a whole.
The command above retains your original folder as `ChatGPT.backup.<suffix>`.
Subsequent runs compare versions normally. ChatGPT's profile/data outside the
installation folder are not removed.

Updates are downloaded, checked for RPM digest integrity, extracted, and
validated **before** the application is closed. Publisher signature trust is
not configured by this script; use packages from sources you trust. Downloads
and redirects require HTTPS. The first download can be large. After a
successful remote installation, the server's ETag is saved so an unchanged
package can be skipped without downloading its payload again. `--force`
bypasses that cache. `--check` can download a changed package but never installs
it or closes the application.

When an update will be installed, the default behavior is to warn, ask permission
if ChatGPT is running, show an optional desktop notification, wait five seconds,
and request shutdown with SIGTERM. Only your processes executing from the
selected installation folder are matched. If they do not exit within 15
seconds, installation stops; no forced kill is performed. ChatGPT remains
closed after an update. Avoid launching it during replacement.

`--yes` gives advance consent to closing. Without it, unattended runs that need
to close the application stop with exit code `3`. `--if-running skip` defers the
update successfully instead. `--close-delay` / `CLOSE_DELAY` accepts 0–60 seconds.

A per-target lock blocks concurrent installers. Extraction and replacement
happen on the target filesystem. The previous folder is moved aside and restored
if replacement fails. `--keep-backup` preserves it after success; otherwise it
is removed. If a later desktop-integration step fails, the valid new application
and the previous backup remain available, and the command reports an error.

Exit codes: `0` means installed, up to date, deferred, or check completed;
`1` means an error; `3` means closing was not authorized. Interrupted runs use
`130` (SIGINT) or `143` (SIGTERM).

## Installation and update logs

Once a new or explicitly forced installation is selected, the installer creates
`logs/` beside the project scripts and writes a separate file such as
`logs/update-20261002T090000+0300.<suffix>.log`. File names are unique even for
attempts starting in the same second. Logs are private and ignored by Git.

Each file includes:

- The old and candidate RPM versions (`not installed` for a first installation,
  or `unknown` for an untracked manual folder).
- The installation location and whether `--force` was requested.
- Start and finish dates/times with a timezone offset.
- Installer output, including errors and rollback messages.
- The final outcome and exit code: installed, deferred, cancelled, failed,
  interrupted, or installed with a later integration/cleanup error.

Deferred or failed attempts are not reported as completed installations.
Equal/older versions, unchanged conditional downloads, and `--check` runs do
not create log files. Failures before a candidate version can be selected
(for example, a failed download) remain in the terminal or scheduler journal.

Logs are written for both manual and scheduled updates. Keep the project
directory writable and remove old log files manually when no longer needed.
The log is flushed before the command exits.

## Automatic updates with the wizard

```bash
./autoupdate-wizard.sh
```

The wizard asks for the install location, latest download or local RPM, daily
or weekly schedule, time, running-app policy, and backup preference. It displays
the settings before enabling them. Choose **skip** to wait until ChatGPT is
closed; choose **close** to consent to warning and closing it during updates.
For a local RPM, replace the selected file yourself when a newer package is
available. The wizard does not discover new files in a downloads directory.

It creates one schedule per user:

- `~/.config/systemd/user/chatgpt-autoupdate.service`
- `~/.config/systemd/user/chatgpt-autoupdate.timer`
- `~/.config/chatgpt-rpm-installer/run-update.sh`
- `~/.config/chatgpt-rpm-installer/update.env`

`XDG_CONFIG_HOME` is honored when set. The updater uses a separate configuration
snapshot; editing the project `.env` does not change an existing schedule.
Rerun the wizard to change it. You can also edit the generated `update.env`
directly for paths and package settings; use the wizard to change consent to
closing the application, which is captured in the runner's `--yes` flag.
The generated runner captures your current tool `PATH` and clears configuration
environment overrides so scheduled behavior follows that snapshot. Keep this
project at its original path, or rerun the wizard after moving it.

Times use the system timezone, with up to five minutes of randomized delay.
Persistent timers catch up on missed checks when your user session starts, so a
check can run soon after setup or login. The user manager normally runs while
you are logged in; the wizard does not enable lingering or change system-wide
settings. See the [systemd timer documentation](https://github.com/systemd/systemd/blob/main/man/systemd.timer.xml).

Inspect or trigger the schedule:

```bash
./autoupdate-wizard.sh --status
systemctl --user list-timers --all chatgpt-autoupdate.timer
journalctl --user -u chatgpt-autoupdate.service
systemctl --user start chatgpt-autoupdate.service
```

Remove automatic updates completely:

```bash
./autoupdate-wizard.sh --remove
```

This stops/disables the managed timer, stops its updater service, and removes
the managed units, runner, configuration, and timer timestamp. It preserves
ChatGPT, the project `.env`, and unrelated units. Files without the wizard's
ownership marker are not overwritten or removed.

## Cron alternative

Use either the wizard or cron to avoid duplicate checks. Cron is optional and
requires a running cron service. Create a wrapper with absolute paths, for
example `~/Programs/update-chatgpt.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
# Add any other directories containing rpm2cpio/cpio/curl on your system.
exec /usr/bin/bash /absolute/path/to/ChatGPT-app-installer/install-chatgpt.sh \
  --config /absolute/path/to/ChatGPT-app-installer/.env \
  --non-interactive --if-running skip
```

Then run `crontab -e` and add a daily check at 09:00 (replace `yourname`):

```cron
0 9 * * * /usr/bin/bash /home/yourname/Programs/update-chatgpt.sh >> /home/yourname/chatgpt-update.log 2>&1
```

To allow closing, change the wrapper to `--non-interactive --yes --if-running
close`. Cron sessions may not have a desktop notification bus; the log still
contains the warning. Missed cron checks are not caught up automatically.

Remove this job with `crontab -e` by deleting its line, then delete your wrapper
and log if desired. **The wizard removes only its systemd schedule**, so it
cannot remove a manually configured cron job. Do not use `crontab -r` unless
you intend to remove all of your cron jobs.

## Project layout and checks

`install-chatgpt.sh`, `setup-wizard.sh`, and `autoupdate-wizard.sh` are small entry points. The shell
modules in `lib/` handle shared helpers, configuration, CLI parsing, RPM version
comparison, package acquisition/extraction, process shutdown, desktop integration,
installation/rollback, guided configuration, update logging, and scheduling.

Run the integration suite with Python 3 (a development dependency only):

```bash
python3 -m unittest discover -s tests -v
for script in install-chatgpt.sh setup-wizard.sh autoupdate-wizard.sh lib/*.sh; do
  bash -n "$script" || exit
done
```

Tests use temporary project copies and homes, deterministic RPM/download fixtures, real `cpio`,
native RPM version comparisons, and real processes. Scheduler management and
desktop registration commands are stubbed. When available, GIO and
`desktop-file-validate` also check a real fixture launcher. Tests never install
the real ChatGPT application or enable a real timer.
