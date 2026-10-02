#!/usr/bin/env python3
"""Integration fixtures: real Bash/cpio/RPM comparisons and real /proc processes.

RPM query/download commands are replaced with deterministic local fixtures.
No user installation, desktop setting, network connection or timer is touched.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REAL_RPM = shutil.which("rpm")
REAL_MV = shutil.which("mv")


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="chatgpt-tests-")
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.project = self.base / "project"
        self.project.mkdir()
        for name in ("install-chatgpt.sh", "autoupdate-wizard.sh", "setup-wizard.sh", ".env.example"):
            shutil.copy2(ROOT / name, self.project / name)
        shutil.copytree(ROOT / "lib", self.project / "lib")
        self.target = self.home / "Programs" / "ChatGPT with spaces"
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items() if k not in (
            "INSTALL_DIR", "DOWNLOAD_LATEST", "RPM_PATH", "RPM_URL",
            "INTEGRATE_DESKTOP", "KEEP_BACKUP", "IF_RUNNING", "CLOSE_DELAY")}
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / ".config"),
                        XDG_DATA_HOME=str(self.home / ".local/share"),
                        PATH=f"{self.bin}:{os.environ['PATH']}", REAL_RPM=REAL_RPM,
                        REAL_MV=REAL_MV, COMMAND_LOG=str(self.base / "commands.log"))
        self.processes = []
        self.script("rpm", '''import json, os, sys
if sys.argv[1] == "--eval":
    os.execv(os.environ["REAL_RPM"], [os.environ["REAL_RPM"], *sys.argv[1:]])
if sys.argv[1] == "--checksig":
    sys.exit(1 if os.environ.get("INTEGRITY_FAIL") else 0)
with open(sys.argv[-1], "rb") as f: data = json.loads(f.readline())
if "FILENAMES" in sys.argv[3]:
    for path, link in data["links"]: print(path + "\\t" + link)
else:
    print("\\t".join([data["name"], data["epoch"], data["version"], data["release"], data["arch"]]))
''')
        self.script("rpm2cpio", '''import sys
with open(sys.argv[1], "rb") as f:
    f.readline()
    sys.stdout.buffer.write(f.read())
''')
        self.script("curl", '''import json, os, pathlib, sys
args = sys.argv[1:]
if os.environ.get("DOWNLOAD_FAIL"): sys.exit(22)
package = pathlib.Path(os.environ["DOWNLOAD_PACKAGE"])
etag = '"' + json.loads(package.open("rb").readline())["version"] + '"'
pathlib.Path(args[args.index("--etag-save") + 1]).write_text(etag)
if "--etag-compare" in args and pathlib.Path(args[args.index("--etag-compare") + 1]).read_text() == etag:
    print("304", end="")
else:
    pathlib.Path(args[args.index("--output") + 1]).write_bytes(package.read_bytes())
    print("200", end="")
''')
        self.script("mv", '''import os, sys
if os.environ.get("FAIL_SWAP") and any(x.endswith("/root") for x in sys.argv[1:]):
    sys.exit(1)
if os.environ.get("FAIL_CONFIG_SAVE") and any("/.chatgpt-env." in x for x in sys.argv[1:]):
    sys.exit(1)
os.execv(os.environ["REAL_MV"], [os.environ["REAL_MV"], *sys.argv[1:]])
''')
        for command in ("systemctl", "notify-send", "xdg-mime", "update-desktop-database", "kbuildsycoca6"):
            self.script(command, '''import os, pathlib, sys
with open(os.environ["COMMAND_LOG"], "a") as f:
    f.write(pathlib.Path(sys.argv[0]).name + " " + " ".join(sys.argv[1:]) + "\\n")
if os.environ.get("SYSTEMCTL_FAIL") and pathlib.Path(sys.argv[0]).name == "systemctl": sys.exit(1)
''')

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        self.temp.cleanup()

    def script(self, name, code):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + code)
        path.chmod(0o755)

    def package(self, version="1.0", epoch="0", release="1", executable=True,
                name="chatgpt", arch=None):
        staging = Path(tempfile.mkdtemp(dir=self.base))
        (staging / "usr/bin").mkdir(parents=True)
        (staging / "usr/lib/chatgpt").mkdir(parents=True)
        links = []
        if executable:
            shutil.copy2(shutil.which("sleep"), staging / "usr/lib/chatgpt/ChatGPT")
            (staging / "usr/bin/chatgpt").symlink_to("../lib/chatgpt/ChatGPT")
            links.append(("/usr/bin/chatgpt", "../lib/chatgpt/ChatGPT"))
        (staging / "payload-version").write_text(version)
        files = ".\n" + "\n".join("./" + str(p.relative_to(staging)) for p in staging.rglob("*")) + "\n"
        payload = subprocess.run(["cpio", "--create", "--format=newc", "--quiet"],
                                 cwd=staging, input=files.encode(), capture_output=True, check=True).stdout
        data = dict(name=name, epoch=epoch, version=version, release=release,
                    arch=arch or os.uname().machine, links=links)
        path = self.base / f"fixture-{len(list(self.base.glob('fixture-*')))}.rpm"
        path.write_bytes(json.dumps(data).encode() + b"\n" + payload)
        return path

    def run_installer(self, package=None, *options, code=0, env=None):
        args = ["bash", str(self.project / "install-chatgpt.sh"), "--no-config", "--target", str(self.target)]
        if package:
            args += ["--rpm", str(package)]
        args += ["--no-integrate", *options]
        result = subprocess.run(args, cwd=self.base, env=env or self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def run_cli(self, *options, code=0, env=None):
        result = subprocess.run(["bash", str(self.project / "install-chatgpt.sh"), *options],
                                cwd=self.base, env=env or self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def version(self):
        return (self.target / "payload-version").read_text()

    def launch(self, target=None):
        process = subprocess.Popen([str((target or self.target) / "usr/bin/chatgpt"), "60"])
        self.processes.append(process)
        return process

    def test_fresh_install_preserves_relative_launcher(self):
        self.run_installer(self.package())
        self.assertEqual(self.version(), "1.0")
        self.assertTrue((self.target / "usr/bin/chatgpt").is_symlink())
        self.assertIn("VERSION=1.0", (self.target / ".chatgpt-install-info").read_text())

    def test_equal_and_older_packages_leave_running_application_untouched(self):
        package = self.package("1.10")
        self.run_installer(package)
        process = self.launch()
        self.assertIn("Already up to date", self.run_installer(package))
        self.assertIn("Already up to date", self.run_installer(self.package("1.9")))
        self.assertEqual(self.version(), "1.10")
        self.assertIsNone(process.poll())

    def test_newer_package_installs_and_retains_requested_backup(self):
        self.run_installer(self.package("1.9"))
        self.run_installer(self.package("1.10"), "--keep-backup")
        self.assertEqual(self.version(), "1.10")
        backup, = self.target.parent.glob(self.target.name + ".backup.*")
        self.assertEqual((backup / "payload-version").read_text(), "1.9")

    def test_epoch_release_and_prerelease_use_native_rpm_ordering(self):
        self.run_installer(self.package("2.0~rc1"))
        self.run_installer(self.package("2.0"))
        self.assertEqual(self.version(), "2.0")
        self.run_installer(self.package("2.0", release="2"))
        self.assertIn("RELEASE=2", (self.target / ".chatgpt-install-info").read_text())
        self.run_installer(self.package("1.0", epoch="1"))
        self.assertEqual(self.version(), "1.0")
        self.run_installer(self.package("99.0", epoch="0"))
        self.assertEqual(self.version(), "1.0")

    def test_force_allows_explicit_downgrade(self):
        self.run_installer(self.package("2.0"))
        self.run_installer(self.package("1.0"), "--force")
        self.assertEqual(self.version(), "1.0")

    def test_check_never_installs_or_closes(self):
        self.run_installer(self.package())
        process = self.launch()
        self.assertIn("newer version", self.run_installer(self.package("2.0"), "--check"))
        self.assertEqual(self.version(), "1.0")
        self.assertIsNone(process.poll())

    def test_check_fresh_target_remains_absent(self):
        self.run_installer(self.package(), "--check")
        self.assertFalse(self.target.exists())

    def test_untracked_manual_extraction_requires_force(self):
        self.target.mkdir(parents=True)
        (self.target / "personal-file").write_text("keep")
        self.assertIn("--force once", self.run_installer(self.package(), code=1))
        self.assertTrue((self.target / "personal-file").exists())
        self.run_installer(self.package(), "--force", "--keep-backup")
        self.assertEqual(self.version(), "1.0")

    def test_process_skip_defers_update(self):
        self.run_installer(self.package())
        process = self.launch()
        self.assertIn("deferring", self.run_installer(self.package("2.0"), "--if-running", "skip"))
        self.assertEqual(self.version(), "1.0")
        self.assertIsNone(process.poll())

    def test_unattended_close_requires_explicit_consent(self):
        self.run_installer(self.package())
        process = self.launch()
        self.assertIn("Update cancelled", self.run_installer(self.package("2.0"), "--non-interactive", code=3))
        self.assertIsNone(process.poll())
        self.assertEqual(self.version(), "1.0")

    def test_consent_warns_and_closes_only_selected_installation(self):
        self.run_installer(self.package())
        process = self.launch()
        other = self.home / "Programs/OtherChatGPT"
        shutil.copytree(self.target, other, symlinks=True)
        other_process = self.launch(other)
        output = self.run_installer(self.package("2.0"), "--yes", "--non-interactive", "--close-delay=0")
        self.assertIn("Save your work", output)
        self.assertEqual(process.wait(timeout=5), -15)
        self.assertIsNone(other_process.poll())
        self.assertEqual(self.version(), "2.0")

    def test_invalid_payload_leaves_application_running_and_installed(self):
        self.run_installer(self.package())
        process = self.launch()
        self.run_installer(self.package("2.0", executable=False), "--yes", code=1)
        self.assertIsNone(process.poll())
        self.assertEqual(self.version(), "1.0")

    def test_failed_swap_restores_backup(self):
        self.run_installer(self.package())
        env = dict(self.env, FAIL_SWAP="1")
        self.assertIn("rolling back", self.run_installer(self.package("2.0"), code=1, env=env))
        self.assertEqual(self.version(), "1.0")
        self.assertFalse(list(self.target.parent.glob(".chatgpt-install.*")))

    def test_application_refusing_sigterm_is_not_killed_or_replaced(self):
        self.run_installer(self.package())
        process = subprocess.Popen([str(self.target / "usr/bin/chatgpt"), "60"],
                                   preexec_fn=lambda: signal.signal(signal.SIGTERM, signal.SIG_IGN))
        self.processes.append(process)
        output = self.run_installer(self.package("2.0"), "--yes", "--close-delay", "0", code=1)
        self.assertIn("did not exit", output)
        self.assertIsNone(process.poll())
        self.assertEqual(self.version(), "1.0")

    def test_failed_initial_swap_does_not_leave_partial_install(self):
        self.run_installer(self.package(), code=1, env=dict(self.env, FAIL_SWAP="1"))
        self.assertFalse(self.target.exists())

    def test_wrong_package_and_architecture_are_rejected(self):
        self.run_installer(self.package(name="another-app"), code=1)
        self.run_installer(self.package(arch="wrong-arch"), code=1)
        self.assertFalse(self.target.exists())

    def test_env_relative_rpm_home_expansion_and_cli_precedence(self):
        package = self.package()
        config = self.base / "custom.env"
        config.write_text(f'INSTALL_DIR="${{HOME}}/Programs/Configured"\nDOWNLOAD_LATEST=false\nRPM_PATH="{package.name}"\nINTEGRATE_DESKTOP=false\n')
        output = self.run_cli("--config", str(config), "--target", str(self.target))
        self.assertIn("Installed", output)
        self.assertEqual(self.version(), "1.0")
        self.assertFalse((self.home / "Programs/Configured").exists())

    def test_environment_overrides_file_and_cli_overrides_environment(self):
        package = self.package()
        config = self.base / "config.env"
        config.write_text('INSTALL_DIR="${HOME}/Programs/FromFile"\nDOWNLOAD_LATEST=true\n')
        env = dict(self.env, INSTALL_DIR=str(self.target), DOWNLOAD_LATEST="false", RPM_PATH=str(package))
        self.run_cli("--config", str(config), "--no-integrate", env=env)
        self.assertEqual(self.version(), "1.0")
        self.run_cli("--config", str(config), "--rpm", str(self.package("2.0")), "--target", str(self.target), "--no-integrate", env=env)
        self.assertEqual(self.version(), "2.0")

    def test_config_is_data_and_never_executes_shell(self):
        sentinel = self.base / "executed"
        config = self.base / "config.env"
        config.write_text(f'INSTALL_DIR={self.home}/Programs/$(touch {sentinel})\nDOWNLOAD_LATEST=false\nRPM_PATH={self.package()}\nINTEGRATE_DESKTOP=false\n')
        self.run_cli("--config", str(config), "--check")
        self.assertFalse(sentinel.exists())

    def test_invalid_options_config_and_unsafe_paths_fail_clearly(self):
        for options in [("--rpm",), ("--latest=no",), ("--wat",), ("--config", "missing"),
                        ("--close-delay", "100"), ("--if-running", "kill"),
                        ("--config", "missing", "--no-config")]:
            self.run_cli(*options, code=1)
        package = self.package()
        for target in [str(self.home), str(self.home / "Programs"), "/"]:
            self.assertIn("unsafe", self.run_installer(package, "--target", target, code=1))
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.target.symlink_to(self.home, target_is_directory=True)
        self.assertIn("symlink", self.run_installer(package, code=1))
        config = self.base / "config.env"
        config.write_text("TYPO=true\n")
        self.assertIn("unknown setting", self.run_cli("--config", str(config), code=1))
        self.run_cli("--config", str(config), "--help")

    def test_desktop_integration_preserves_existing_command(self):
        command = self.home / ".local/bin/chatgpt"
        command.parent.mkdir(parents=True)
        command.write_text("personal command")
        self.run_cli("--no-config", "--rpm", str(self.package()), "--target", str(self.target))
        self.assertEqual(command.read_text(), "personal command")
        desktop = (self.home / ".local/share/applications/chatgpt.desktop").read_text()
        self.assertIn(f'Exec="{self.target}/usr/bin/chatgpt" %U', desktop)
        self.assertIn("xdg-mime default chatgpt.desktop", (self.base / "commands.log").read_text())

    @unittest.skipUnless(shutil.which("gio") and shutil.which("desktop-file-validate"),
                         "GIO desktop launcher tools are optional")
    def test_native_desktop_launch_with_special_install_path(self):
        self.target = self.home / 'Programs' / 'ChatGPT % $ " \\ quote'
        self.run_cli("--no-config", "--rpm", str(self.package()), "--target", str(self.target))
        desktop = self.home / ".local/share/applications/chatgpt.desktop"
        subprocess.run(["desktop-file-validate", str(desktop)], capture_output=True, check=True)
        marker = self.base / "launched"
        (self.target / "usr/lib/chatgpt/ChatGPT").write_text(
            "#!/usr/bin/env bash\nprintf launched > " + shlex.quote(str(marker)) + "\n")
        result = subprocess.run(["gio", "launch", str(desktop)], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        import time
        for _ in range(50):
            if marker.exists():
                break
            time.sleep(0.02)
        self.assertEqual(marker.read_text(), "launched")

    def test_download_conditional_cache_and_failure(self):
        env = dict(self.env, DOWNLOAD_PACKAGE=str(self.package()))
        self.run_installer(None, env=env)
        process = self.launch()
        self.assertIn("unchanged", self.run_installer(None, env=env))
        self.assertIsNone(process.poll())
        self.run_installer(None, code=1, env=dict(env, DOWNLOAD_FAIL="1"))
        self.assertEqual(self.version(), "1.0")
        env["DOWNLOAD_PACKAGE"] = str(self.package("2.0"))
        self.run_installer(None, "--yes", "--close-delay", "0", env=env)
        self.assertEqual(self.version(), "2.0")

    def test_failed_digest_does_not_stop_or_replace_application(self):
        self.run_installer(self.package())
        process = self.launch()
        self.run_installer(self.package("2.0"), code=1, env=dict(self.env, INTEGRITY_FAIL="1"))
        self.assertIsNone(process.poll())
        self.assertEqual(self.version(), "1.0")

    def wizard(self, options=(), answers="", code=0, env=None):
        result = subprocess.run(["bash", str(self.project / "autoupdate-wizard.sh"), *options],
                                env=env or self.env, input=answers, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    @property
    def update_dir(self):
        return self.home / ".config/chatgpt-rpm-installer"

    @property
    def unit_dir(self):
        return self.home / ".config/systemd/user"

    def test_wizard_setup_runner_status_and_complete_removal(self):
        package = self.package()
        answers = f"{self.target}\nlocal\n{package}\ndaily\n10:30\nskip\nyes\nyes\n"
        self.wizard(("--no-config",), answers)
        timer = self.unit_dir / "chatgpt-autoupdate.timer"
        self.assertIn("OnCalendar=*-*-* 10:30:00", timer.read_text())
        self.assertIn("Persistent=true", timer.read_text())
        runner = self.update_dir / "run-update.sh"
        self.assertNotIn("--yes", runner.read_text())
        result = subprocess.run(["bash", str(runner)], cwd="/tmp", env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.version(), "1.0")
        self.assertIn("timer", self.wizard(("--status",)))
        unrelated = self.unit_dir / "unrelated.timer"
        unrelated.write_text("keep")
        self.wizard(("--remove",))
        self.assertFalse(timer.exists())
        self.assertFalse((self.unit_dir / "chatgpt-autoupdate.service").exists())
        self.assertFalse(self.update_dir.exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue(self.target.exists())
        self.wizard(("--remove",))

    def test_wizard_weekly_close_and_reconfigure(self):
        answers = f"{self.target}\nlatest\nweekly\n23:30\nFri\nclose\nno\nyes\n"
        self.wizard(("--no-config",), answers)
        self.assertIn("OnCalendar=Fri *-*-* 23:30:00", (self.unit_dir / "chatgpt-autoupdate.timer").read_text())
        self.assertIn("--yes", (self.update_dir / "run-update.sh").read_text())
        answers = f"{self.target}\nlatest\ndaily\n09:00\nskip\nno\nyes\n"
        self.wizard(("--no-config",), answers)
        self.assertIn("OnCalendar=*-*-* 09:00:00", (self.unit_dir / "chatgpt-autoupdate.timer").read_text())

    def test_wizard_handles_special_path_characters_without_execution(self):
        self.target = self.home / 'Programs' / 'ChatGPT % $ " quote'
        package = self.package()
        self.wizard(("--no-config",), f"{self.target}\nlocal\n{package}\ndaily\n09:00\nskip\nno\nyes\n")
        result = subprocess.run(["bash", str(self.update_dir / "run-update.sh")],
                                env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.version(), "1.0")

    def test_wizard_cancel_and_invalid_input_write_nothing(self):
        self.wizard(("--no-config",), f"{self.target}\nlatest\ndaily\n09:00\nskip\nno\nno\n")
        self.assertFalse(self.unit_dir.exists())
        self.wizard(("--no-config",), f"{self.target}\nlatest\ndaily\n25:00\n", code=1)
        self.assertFalse(self.unit_dir.exists())
        self.wizard(("--no-config",), "", code=1)

    def test_wizard_refuses_unmanaged_files_and_missing_user_manager(self):
        self.unit_dir.mkdir(parents=True)
        timer = self.unit_dir / "chatgpt-autoupdate.timer"
        timer.write_text("user's own timer")
        self.assertIn("unmanaged", self.wizard(("--remove",), code=1))
        self.assertEqual(timer.read_text(), "user's own timer")
        self.wizard(("--no-config",), code=1, env=dict(self.env, SYSTEMCTL_FAIL="1"))

    def test_concurrent_update_is_locked(self):
        self.target.parent.mkdir(parents=True)
        lock = self.target.parent / f".{self.target.name}.install.lock"
        with lock.open("w") as handle:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertIn("Another installer", self.run_installer(self.package(), code=1))

    def setup_wizard(self, answers="", options=(), code=0, env=None):
        result = subprocess.run(["bash", str(self.project / "setup-wizard.sh"), "--no-color", *options],
                                cwd=self.base, env=env or self.env, input=answers,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_setup_generates_private_latest_configuration_without_installing(self):
        output = self.setup_wizard(f"{self.target}\n1\n2\n1\n1\n1\n2\n")
        config = self.project / ".env"
        text = config.read_text()
        self.assertIn(f'INSTALL_DIR="{self.target}"', text)
        self.assertIn("DOWNLOAD_LATEST=true", text)
        self.assertIn("INTEGRATE_DESKTOP=false", text)
        self.assertIn("IF_RUNNING=skip", text)
        self.assertIn("KEEP_BACKUP=true", text)
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertIn("does not create a background schedule", output)
        self.assertIn("Step 7 of 7", output)
        self.assertFalse(self.target.exists())
        self.assertFalse((self.project / "logs").exists())
        self.assertFalse(self.unit_dir.exists())

    def test_setup_local_configuration_is_consumed_by_installer(self):
        package = self.package()
        self.setup_wizard(f"{self.target}\n2\n{package}\n2\n2\n10\n2\n1\n2\n")
        config = self.project / ".env"
        self.assertIn("DOWNLOAD_LATEST=false", config.read_text())
        self.assertIn("CLOSE_DELAY=10", config.read_text())
        self.run_cli()
        self.assertEqual(self.version(), "1.0")

    def test_setup_reprompts_invalid_values_and_preserves_literal_paths(self):
        package = self.package()
        self.target = self.home / "Programs" / 'ChatGPT $HOME " test'
        output = self.setup_wizard(f"{self.home}\n{self.target}\n3\n2\nmissing.rpm\n{package}\n2\n2\n99\n05\n2\n1\n2\n")
        self.assertIn("unsafe installation target", output)
        self.assertIn("Please enter 1 or 2", output)
        self.assertIn("readable RPM", output)
        self.assertIn("whole number from 0 through 60", output)
        self.run_cli()
        self.assertEqual(self.version(), "1.0")

    def test_setup_cancel_and_eof_leave_existing_config_unchanged(self):
        config = self.project / ".env"
        original = f'INSTALL_DIR="{self.target}"\nIF_RUNNING=skip\n'
        config.write_text(original)
        self.setup_wizard("\n1\n2\n1\n2\n2\n")
        self.assertEqual(config.read_text(), original)
        self.assertFalse(list(self.project.glob(".env.backup.*")))
        self.setup_wizard()
        self.assertEqual(config.read_text(), original)

    def test_setup_custom_destination_and_existing_config_backup(self):
        config = self.base / "configuration with spaces/update.env"
        config.parent.mkdir()
        original = f'INSTALL_DIR="{self.target}"\nDOWNLOAD_LATEST=true\nIF_RUNNING=skip\n'
        config.write_text(original)
        self.setup_wizard("\n1\n2\n1\n2\n1\n2\n", ("--output", str(config)))
        backup, = config.parent.glob("update.env.backup.*")
        self.assertEqual(backup.read_text(), original)
        self.assertFalse((self.project / ".env").exists())
        self.run_cli("--config", str(config), "--rpm", str(self.package()), "--no-integrate")
        self.assertEqual(self.version(), "1.0")

    def test_setup_offers_and_hands_config_to_automatic_update_wizard(self):
        package = self.package()
        setup = f"{self.target}\n2\n{package}\n2\n1\n2\n1\n1\n"
        schedule = "\n\n\ndaily\n10:30\nskip\nno\nyes\n"
        self.setup_wizard(setup + schedule)
        config = (self.update_dir / "update.env").read_text()
        self.assertIn(f'INSTALL_DIR="{self.target}"', config)
        self.assertIn(f'RPM_PATH="{package}"', config)
        self.assertIn("INTEGRATE_DESKTOP=false", config)
        self.assertIn("OnCalendar=*-*-* 10:30:00", (self.unit_dir / "chatgpt-autoupdate.timer").read_text())

    def test_setup_retains_config_when_scheduler_is_unavailable(self):
        output = self.setup_wizard(f"{self.target}\n1\n2\n1\n2\n1\n1\n", code=1,
                                  env=dict(self.env, SYSTEMCTL_FAIL="1"))
        self.assertTrue((self.project / ".env").exists())
        self.assertIn(".env is saved", output)
        self.assertFalse(self.unit_dir.exists())

    def test_setup_rejects_symlink_destination_and_supports_help(self):
        original = self.base / "original.env"
        original.write_text("unchanged")
        output = self.base / "symlink.env"
        output.symlink_to(original)
        self.setup_wizard(options=("--output", str(output)), code=1)
        self.assertEqual(original.read_text(), "unchanged")
        self.setup_wizard(options=("--help",))
        self.setup_wizard(options=("--output",), code=1)

    def test_setup_save_failure_preserves_original_and_reports_failure(self):
        config = self.project / ".env"
        original = f'INSTALL_DIR="{self.target}"\nDOWNLOAD_LATEST=true\nIF_RUNNING=skip\n'
        config.write_text(original)
        output = self.setup_wizard("\n1\n2\n1\n2\n1\n", code=1,
                                   env=dict(self.env, FAIL_CONFIG_SAVE="1"))
        self.assertEqual(config.read_text(), original)
        self.assertNotIn("Configuration saved", output)
        self.assertFalse(list(self.project.glob(".chatgpt-env.*")))

    def test_styled_setup_runs_in_a_real_terminal(self):
        import errno
        import pty
        import select
        import time
        master, slave = pty.openpty()
        env = dict(self.env, TERM="xterm-256color")
        env.pop("NO_COLOR", None)
        process = subprocess.Popen(["bash", str(self.project / "setup-wizard.sh")],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        captured = b""
        try:
            os.write(master, f"{self.target}\n1\n2\n1\n2\n1\n2\n".encode())
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if not ready:
                    if process.poll() is not None:
                        break
                    continue
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                captured += chunk
            self.assertEqual(process.wait(timeout=2), 0, captured.decode(errors="replace"))
            self.assertIn(b"\x1b[H\x1b[2J", captured)
            self.assertIn(b"Step 7 of 7", captured)
            self.assertIn(b"Configuration ready", captured)
            self.assertTrue((self.project / ".env").exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def update_logs(self):
        return sorted((self.project / "logs").glob("*.log"))

    def test_logs_record_each_transition_with_times_and_output(self):
        self.run_installer(self.package())
        self.assertEqual(len(self.update_logs()), 1)
        first = self.update_logs()[0].read_text()
        self.assertIn("From version: not installed", first)
        self.assertIn("To version: 0:1.0-1", first)
        self.run_installer(self.package("2.0"))
        self.assertEqual(len(self.update_logs()), 2)
        update = next(path for path in self.update_logs() if "To version: 0:2.0-1" in path.read_text())
        text = update.read_text()
        self.assertIn("From version: 0:1.0-1", text)
        self.assertIn("Outcome: installed", text)
        self.assertIn("Exit code: 0", text)
        self.assertIn("Extracting RPM", text)
        self.assertRegex(text, r"Started at: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d")
        self.assertRegex(text, r"Finished at: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d")
        self.assertEqual(update.stat().st_mode & 0o777, 0o600)

    def test_checks_equal_older_and_conditional_downloads_do_not_create_logs(self):
        package = self.package()
        self.run_installer(package, "--check")
        self.assertFalse((self.project / "logs").exists())
        self.run_installer(package)
        self.run_installer(package)
        self.run_installer(self.package("0.9"))
        self.run_installer(self.package("2.0"), "--check")
        self.assertEqual(len(self.update_logs()), 1)
        self.run_installer(None, "--force", env=dict(self.env, DOWNLOAD_PACKAGE=str(package)))
        self.run_installer(None, env=dict(self.env, DOWNLOAD_PACKAGE=str(package)))
        self.assertEqual(len(self.update_logs()), 2)

    def test_failed_and_deferred_attempts_have_correct_log_outcomes(self):
        self.run_installer(self.package())
        self.run_installer(self.package("2.0"), code=1, env=dict(self.env, FAIL_SWAP="1"))
        failed = next(path.read_text() for path in self.update_logs() if "To version: 0:2.0-1" in path.read_text())
        self.assertIn("Outcome: failed", failed)
        self.assertIn("rolling back", failed)
        self.assertIn("Exit code: 1", failed)
        process = self.launch()
        self.run_installer(self.package("3.0"), "--if-running", "skip")
        deferred = next(path.read_text() for path in self.update_logs() if "To version: 0:3.0-1" in path.read_text())
        self.assertIn("Outcome: deferred", deferred)
        self.assertNotIn("Outcome: installed", deferred)
        self.assertIsNone(process.poll())
        self.run_installer(self.package("4.0"), "--non-interactive", code=3)
        cancelled = next(path.read_text() for path in self.update_logs() if "To version: 0:4.0-1" in path.read_text())
        self.assertIn("Outcome: cancelled", cancelled)

    def test_invalid_log_directory_leaves_running_installation_untouched(self):
        self.run_installer(self.package())
        shutil.rmtree(self.project / "logs")
        (self.project / "logs").symlink_to(self.base, target_is_directory=True)
        process = self.launch()
        self.assertIn("logs path", self.run_installer(self.package("2.0"), "--yes", code=1))
        self.assertIsNone(process.poll())
        self.assertEqual(self.version(), "1.0")

    def test_interrupted_update_finishes_log_and_leaves_old_version(self):
        import time
        self.run_installer(self.package())
        ready = self.base / "extracting"
        self.script("rpm2cpio", '''import os, pathlib, sys, time
pathlib.Path(os.environ["EXTRACT_READY"]).write_text("ready")
time.sleep(20)
''')
        process = subprocess.Popen(["bash", str(self.project / "install-chatgpt.sh"),
                                    "--no-config", "--target", str(self.target),
                                    "--rpm", str(self.package("2.0")), "--no-integrate"],
                                   env=dict(self.env, EXTRACT_READY=str(ready)),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(ready.exists())
            os.killpg(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143, stdout + stderr)
            log = next(path.read_text() for path in self.update_logs() if "To version: 0:2.0-1" in path.read_text())
            self.assertIn("Outcome: interrupted", log)
            self.assertIn("Finished at:", log)
            self.assertEqual(self.version(), "1.0")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
