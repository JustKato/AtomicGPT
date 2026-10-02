# Configuration

[Back to the README](../README.md) · [Setup wizard and commands](usage.md)

Run `./setup-wizard.sh` to choose your settings, or copy
[.env.example](../.env.example) to `.env` and edit it yourself.
The installer reads the `.env` beside its scripts even when your working
directory is somewhere else.

Settings apply in this order: built-in defaults, the config file, exported
environment variables, then CLI options. Later values override earlier ones.
Use `--config FILE` for another file or `--no-config` to ignore the project file.

## Settings

- `INSTALL_DIR`: the application folder, defaulting to `~/Programs/ChatGPT`.
- `DOWNLOAD_LATEST`: `true` to fetch `RPM_URL`, or `false` to use `RPM_PATH`.
- `RPM_PATH`: a local file or trusted HTTPS URL. The setup wizard asks for a
  local file when you disable downloads.
- `RPM_URL`: the latest-package endpoint. The default is OpenAI's RPM URL in
  `.env.example`.
- `INTEGRATE_DESKTOP`: `true` to create a command, desktop entry, and URI handler.
- `KEEP_BACKUP`: `true` to keep the previous folder after a successful update.
- `IF_RUNNING`: `close` to ask permission to close ChatGPT, or `skip` to defer.
- `CLOSE_DELAY`: the warning delay before closing, from 0 through 60 seconds.

## File format and paths

Use literal `KEY=value` lines, with optional surrounding single or double quotes.
Blank lines and full-line comments are fine. Booleans must be `true` or `false`;
the parser rejects unknown settings. It doesn't execute shell code, accept
`export` declarations, or support inline comments.

Paths can start with `~`, `$HOME`, or `${HOME}`. Other variables aren't expanded.
Use an absolute or home-relative install location. Relative `RPM_PATH` values
resolve beside the config file; a relative CLI `--rpm` path resolves from your
current directory.

## Using a local RPM on every run

Choose a local package in the setup wizard, or copy
[.env.example](../.env.example) to `.env` and set:

```dotenv
INSTALL_DIR="${HOME}/Programs/ChatGPT"
DOWNLOAD_LATEST=false
RPM_PATH="/home/yourname/Downloads/chatgpt.x86_64.rpm"
```

Set `DOWNLOAD_LATEST=true` to fetch the latest package whenever you run the
installer. This controls downloads; it doesn't schedule anything. Use the
[auto-update wizard](automatic-updates.md) to set up a schedule.

Choose a folder dedicated to ChatGPT. Updates replace its contents, so keep
unrelated files elsewhere.
