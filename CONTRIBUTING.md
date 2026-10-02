# Contributing to AtomicGPT

Bug reports and small, focused pull requests are welcome. For a larger change,
open an issue first so we can agree on the behavior before you spend time on it.

## Working on the scripts

Keep the entry scripts small and put shared code in `lib/`. Preserve the
installer's behavior around version comparisons, backups, and closing a running
application. The scripts should work with Bash 4.3 and the tools listed in the
[usage guide](docs/usage.md#requirements).

Use temporary directories for tests. A test must not modify someone's real
installation, `.env`, desktop settings, or scheduled jobs. The existing suite
copies the project into temporary folders and stubs commands that change those
settings. It uses real RPM version comparisons, `cpio`, and fixture processes.

## Before opening a pull request

Run these from the project directory:

```bash
for script in install-chatgpt.sh setup-wizard.sh autoupdate-wizard.sh lib/*.sh; do
  bash -n "$script" || exit
done
shellcheck --severity=warning --exclude=SC2034 install-chatgpt.sh setup-wizard.sh autoupdate-wizard.sh lib/*.sh
python3 -m unittest discover -s tests -v
```

Python 3 and ShellCheck are development tools; users don't need them to install
ChatGPT. We exclude SC2034 because the shell modules share global variables.
When GIO and `desktop-file-validate` are available, the suite also exercises a
fixture desktop launcher. GitHub runs these checks on pushes and pull requests.

Add a regression test for behavior changes and update the docs if a command or
setting changes. Include the checks you ran in the pull request description.

For bug reports, include your distribution, the AtomicGPT version, the command
you ran, and the relevant output. Remove private information from logs before
posting them.
