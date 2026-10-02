# Updates, backups, and logs

[Back to the README](../README.md) · [Automatic updates](automatic-updates.md)

Run `./install-chatgpt.sh` again to check for a newer package. Use `--check`
to compare versions without installing it or closing ChatGPT.

## Version checks

AtomicGPT records the installed RPM epoch, version, and release in
`.chatgpt-install-info` inside the application folder. It uses RPM's ordering,
including packaging revisions and prerelease versions. See
[RPM's version documentation](https://rpm.org/docs/6.0.x/man/rpm-version.7).

Equal or older versions leave the current installation running. `--force`
allows a reinstall, downgrade, or replacement of a folder without a version
record. See [manual installations](#adopting-a-manually-extracted-installation)
if you've been extracting RPMs by hand.
AtomicGPT doesn't launch the GUI to guess an untracked folder's version.

## Downloads

Downloads and redirects require HTTPS. AtomicGPT checks the RPM digests before
extracting it but doesn't establish trust in a publisher's signing key.
Use a source you trust. After a successful remote installation, it saves the
ETag so an unchanged package can skip the next payload download. `--force`
bypasses that cache. `--check` may download a changed RPM, but won't install it
or close ChatGPT.

The first download can be large.

## Closing ChatGPT

Save your work before agreeing to close ChatGPT for an update.
The installer stages and validates the package before asking ChatGPT to exit.
It warns you, asks for consent, waits for `CLOSE_DELAY` (five seconds by default),
and sends SIGTERM to
your processes running from the chosen install folder. It stops if they haven't
exited within 15 seconds. It doesn't force-kill them or reopen the app afterward.
Avoid launching ChatGPT during replacement.

`--yes` supplies consent for unattended closing. Without it, an unattended run
that needs to close the app exits with code `3`. `--if-running skip` defers the
update and exits successfully.

## Replacement and backups

Choose a folder dedicated to ChatGPT: updates replace its contents. Your
profile outside that folder stays in place.

A lock blocks concurrent installers for the same target. Staging and replacement
use the target's filesystem. AtomicGPT moves the previous folder aside and
restores it if replacement fails. It removes the backup after success unless
you chose `--keep-backup`. A later desktop-integration failure leaves the valid
new app and previous backup available, and reports an error.

## Adopting a manually extracted installation

A folder you've extracted by hand has no record of which RPM it came from.
Run this once to replace it, keep the old folder, and start tracking versions:

```bash
./install-chatgpt.sh --target "$HOME/Programs/ChatGPT" --force --keep-backup
```

The original stays in `ChatGPT.backup.<suffix>`. Normal runs then compare
versions. Use `--force` with care: it also allows reinstalls and downgrades.

## Logs and exit codes

AtomicGPT creates `logs/` next to the scripts once it selects an installation
or update attempt. Each private log has a unique name and includes the old and
candidate versions, target, `--force` setting, start and finish times with
timezone offsets, installer output, outcome, and exit code.

A first install uses `not installed` as its old version. An untracked folder
uses `unknown`. Outcomes distinguish installed, deferred, cancelled, failed,
interrupted, and installed with a later integration or cleanup error.

Equal/older versions, unchanged downloads, and `--check` don't create logs.
Errors before selecting a candidate, such as download failures, appear in the
terminal or scheduler journal. Manual and scheduled attempts use the same logs.
The installer flushes the final record before exiting.

Git ignores `logs/`. Keep the project writable, and delete old logs when you
no longer need them. For checks that don't produce an installation log, see the
[scheduler journal and cron instructions](automatic-updates.md).

Exit codes are:

- `0`: installed, up to date, deferred, or check completed.
- `1`: an error.
- `3`: closing wasn't authorized.
- `130`: SIGINT interruption.
- `143`: SIGTERM interruption.
