# AtomicGPT

Install and update ChatGPT in `~/Programs/ChatGPT` on an atomic Linux desktop.

I keep apps in `~/Programs`. AtomicGPT grew out of extracting ChatGPT RPMs by
hand and wanting the next update to take care of itself. It downloads the latest
RPM or uses one you've saved, checks versions, and adds a desktop launcher.

## Get started

Download or clone this repository, then open a terminal in its folder.
Run these as your normal user:

```bash
./setup-wizard.sh
./install-chatgpt.sh
```

The wizard helps you choose an install folder and download settings, saves them
in `.env`, and offers to set up automatic updates. You'll need x86_64 Linux,
Bash 4.3+, `rpm` with Lua support, `rpm2cpio`, GNU `cpio`, and `curl` 7.68+.
See the [full requirements](docs/usage.md#requirements) for the other tools.

After installation, open ChatGPT from your application menu or run:

```bash
~/Programs/ChatGPT/usr/bin/chatgpt
```

If you already have an RPM, you can install it directly:

```bash
./install-chatgpt.sh --rpm ./chatgpt.x86_64.rpm
```

## Keep it updated

Run `./install-chatgpt.sh` again. It installs a newer version and skips equal
or older ones. Before closing a running ChatGPT, it warns you and asks for
permission. Save your work first.

For daily or weekly checks, run `./autoupdate-wizard.sh`. You can choose to
wait while ChatGPT is open or allow the updater to warn and close it.
Remove the schedule with `./autoupdate-wizard.sh --remove`; ChatGPT stays installed.
Keep this project in a permanent, writable folder if you schedule updates.

## Guides

- [Setup and CLI usage](docs/usage.md): requirements, wizard options, commands, and desktop integration.
- [Configuration](docs/configuration.md): `.env` settings, custom install folders, and local RPMs.
- [Updates, backups, and logs](docs/updates-and-logs.md): version checks, manual installations, closing behavior, and update history.
- [Automatic updates](docs/automatic-updates.md): systemd timers, checking or removing schedules, and cron.

AtomicGPT extracts the RPM into your folder; your desktop still needs ChatGPT's
system libraries and sandbox support. It checks package digests but doesn't
establish trust in a publisher's signing key. Use RPMs from sources you trust.

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

AtomicGPT is a community tool, unaffiliated with OpenAI, and doesn't redistribute
ChatGPT. The [MIT license](LICENSE) covers these scripts, not the application.
