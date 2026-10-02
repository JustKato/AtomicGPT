# Scheduling AtomicGPT updates

[Back to the README](../README.md) · [Configuration](configuration.md) · [Updates and logs](updates-and-logs.md)

The [setup wizard](../README.md#get-started) offers to open the scheduling wizard,
or you can run it yourself:

```bash
./autoupdate-wizard.sh
```

Choose the installation folder, latest download or a local RPM, daily or weekly
checks, time, running-app policy, and backups. The wizard shows the choices
before enabling the schedule. `--config FILE` uses another `.env` as the defaults;
`--no-config` ignores the project file.

Choose `skip` to wait until ChatGPT is closed. Choose `close` to give advance
consent to warn and close it for updates. With a local RPM, you'll need to replace
the chosen file yourself when a newer version is available; the updater doesn't
search your Downloads folder for new files.

## The systemd user timer

A new setup creates:

- `~/.config/systemd/user/atomicgpt-autoupdate.service`
- `~/.config/systemd/user/atomicgpt-autoupdate.timer`
- `~/.config/atomicgpt/run-update.sh`
- `~/.config/atomicgpt/update.env`

AtomicGPT uses `XDG_CONFIG_HOME` instead of `~/.config` if you've set it.
It stores a snapshot of your choices in `update.env`; changes to the project
`.env` don't alter an existing schedule. Rerun the wizard to change settings.
You can edit `update.env` for paths and package settings, but use the wizard
to change consent to closing the app.

The runner saves the tool `PATH` from setup and clears exported configuration
overrides before loading its snapshot. Keep the project at that path or rerun
the wizard after moving it.

Checks follow the system timezone and have up to five minutes of randomized
delay. The persistent timer catches up on missed checks when your user session
starts, so it may run soon after setup or login. The wizard doesn't enable
lingering; your user manager normally runs while you're logged in. See
[systemd's timer documentation](https://github.com/systemd/systemd/blob/main/man/systemd.timer.xml).

Check the schedule, read the journal, or trigger a check:

```bash
./autoupdate-wizard.sh --status
systemctl --user list-timers --all atomicgpt-autoupdate.timer
journalctl --user -u atomicgpt-autoupdate.service
systemctl --user start atomicgpt-autoupdate.service
```

Installation and update attempts also write files to the project's `logs/`
folder. See [updates and logs](updates-and-logs.md#logs-and-exit-codes) for what
each file records.

### Schedules from before the AtomicGPT rename

The wizard recognizes the older `chatgpt-autoupdate` units and
`~/.config/chatgpt-rpm-installer/` folder. If you already have that schedule,
it updates it in place rather than creating a second timer. `--status` prints
the active names and journal command. `--remove` works with either layout.

## Removing automatic updates

```bash
./autoupdate-wizard.sh --remove
```

This disables and stops the managed timer, stops its service, clears the timer
timestamp, and removes the units, runner, and generated configuration.
ChatGPT and the project's `.env` stay in place. The wizard refuses to overwrite
or remove files it doesn't recognize as its own.

## Using cron instead

Use one scheduler to avoid duplicate checks. Cron needs a running cron service
and doesn't catch up on checks missed while the machine was off.

Create a wrapper such as `~/Programs/update-atomicgpt.sh`, with absolute paths
to your checkout and config:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
# Add directories containing rpm2cpio/cpio/curl if needed.
exec /usr/bin/bash /absolute/path/to/AtomicGPT/install-chatgpt.sh \
  --config /absolute/path/to/AtomicGPT/.env \
  --non-interactive --if-running skip
```

Run `crontab -e` and add a daily check at 09:00, replacing `yourname`:

```cron
0 9 * * * /usr/bin/bash /home/yourname/Programs/update-atomicgpt.sh >> /home/yourname/atomicgpt-update.log 2>&1
```

To allow closing ChatGPT, change the wrapper's flags to:

```bash
--non-interactive --yes --if-running close
```

Cron may not have access to your desktop notification bus; warnings still
appear in its log. To remove this schedule, delete its line with `crontab -e`,
then delete the wrapper and log if you don't need them. The wizard removes its
systemd schedule, not a manually configured cron job. `crontab -r` removes
all of your cron jobs, so don't use it to remove just this one.
