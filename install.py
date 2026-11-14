#!/usr/bin/env python3
"""Installer for this repo (Textual TUI), shipped on the ISO as `os-install` (see modules/iso.nix).

Asks everything first (network, config version, hostname, disk, desktop, options, GitHub login, password),
then wipes the disk and installs unattended behind one progress bar. Full log: /tmp/os-install.log
"""
import asyncio
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen, Screen
from textual.widgets import (Button, Checkbox, Footer, Header, Input, Label, LoadingIndicator, OptionList,
                             ProgressBar, RichLog, SelectionList, Static)
from textual.widgets.option_list import Option

REPO = os.environ.get("REPO", "https://github.com/justinforlenza/os")  # override for VM testing
OWNER_REPO = "justinforlenza/os"
USER = "justin"
CFG = Path("/tmp/cfg")
LOG = Path("/tmp/os-install.log")
# If GitHub can't be read (offline, private repo), use the ISO's copy instead of asking for a login
ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
STEPS = ["Network", "Config", "Hostname", "Disk", "Desktop", "Wallpapers", "Options", "GitHub", "Password", "Summary",
         "Install", "Done"]
PHASES = ["Partition disk", "Write host config", "Plan downloads", "Download packages", "Install bootloader",
          "Set password", "Push to GitHub", "Finish"]
GH_CODE = re.compile(r"\b[A-Z0-9]{4}-[A-Z0-9]{4}\b")


# ------------------------------------------------------------------ helpers
class CommandError(Exception):
    pass


def log(line: str) -> None:
    with LOG.open("a") as f:
        f.write(line + "\n")


def out(*cmd: str) -> str:
    """Quick command, stdout only."""
    return subprocess.run(cmd, capture_output=True, text=True, env=ENV).stdout.strip()


async def run(*cmd, cwd=None, input: str | None = None, on_line=None, check: bool = True) -> tuple[int, str]:
    """Run a command, logging and streaming its output (stdout+stderr) line by line."""
    cmd = [str(c) for c in cmd]
    log("$ " + " ".join(cmd))
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=cwd, env=ENV, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        stdin=asyncio.subprocess.PIPE if input is not None else asyncio.subprocess.DEVNULL)
    if input is not None:
        proc.stdin.write(input.encode())
        await proc.stdin.drain()
        proc.stdin.close()
    lines = []
    async for raw in proc.stdout:
        line = raw.decode(errors="replace").rstrip()
        lines.append(line)
        log(line)
        if on_line:
            on_line(line)
    rc = await proc.wait()
    if check and rc:
        raise CommandError(f"{cmd[0]} failed (exit {rc})\n" + "\n".join(lines[-5:]))
    return rc, "\n".join(lines)


async def online() -> bool:
    rc, _ = await run("curl", "-sfI", "--max-time", "5", "https://cache.nixos.org", check=False)
    return rc == 0


def bars(signal: int) -> str:
    return "▂▄▆█"[: max(1, (signal + 24) // 25)].ljust(4)


def list_disks() -> list[tuple[str, str, str]]:
    """(by-id path, model, size): one entry per physical disk, minus the installer medium."""
    src = out("findmnt", "-no", "SOURCE", "/iso")
    iso = os.path.realpath(src) if src else ""
    parent = out("lsblk", "-ndo", "PKNAME", iso) if iso else ""
    iso_disk = f"/dev/{parent}" if parent else iso  # a whole-device medium (e.g. a CD) has no parent
    seen, disks = set(), []
    for dev in sorted(glob.glob("/dev/disk/by-id/*")):
        real = os.path.realpath(dev)
        if "-part" in dev or real in seen or real == iso_disk:
            continue
        seen.add(real)
        model, _, size = out("lsblk", "-dno", "MODEL,SIZE", dev).rpartition(" ")
        disks.append((dev, model.strip() or Path(dev).name, size))
    return disks


# ------------------------------------------------------------------ layout
class Sidebar(Static):
    """Step list on the left: done steps ticked, the current one highlighted."""

    def __init__(self, current: str) -> None:
        super().__init__(id="sidebar")
        self.current = current

    def render(self) -> str:
        here = STEPS.index(self.current)
        lines = ["[b]NixOS[/b]", "[dim]installer[/dim]", ""]
        for i, step in enumerate(STEPS):
            if i < here:
                lines.append(f"[green]✓[/green] [dim]{step}[/dim]")
            elif i == here:
                lines.append(f"[b reverse] ▸ {step} [/]")
            else:
                lines.append(f"  [dim]{step}[/dim]")
        return "\n".join(lines)


class Step(Screen):
    """Every page: header, sidebar, a titled body, footer with keys."""
    STEP = ""
    HEADING = ""

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            yield Sidebar(self.STEP)
            with Vertical(id="body"):
                yield Static(self.HEADING, classes="heading")
                yield from self.body()
        yield Footer()

    def body(self):
        return []

    @property
    def state(self) -> dict:
        return self.app.state

    def heading(self, text: str) -> None:
        self.query_one(".heading", Static).update(text)


class Question(Step):
    """Question pages can go back with Esc (the stack starts at Hostname)."""
    BINDINGS = [("escape", "back", "Back")]

    def action_back(self) -> None:
        if not isinstance(self, HostnameScreen):
            self.app.pop_screen()


# ------------------------------------------------------------------ network
class StartScreen(Step):
    STEP, HEADING = "Network", "Connecting"

    def body(self):
        yield Static("Waiting for the network…", classes="muted")
        yield LoadingIndicator()

    def on_mount(self) -> None:
        self.check()

    @work(exclusive=True)
    async def check(self) -> None:
        await run("nm-online", "-q", "-t", "20", check=False)  # at boot, give wired DHCP a moment
        if await online():
            self.app.after_network()
        else:
            self.app.switch_screen(WifiScreen())


class DownloadScreen(Step):
    """Fetch nixpkgs and the config's other pinned inputs (about 50 MB) while still on the network step, so reading
    the options and the install itself don't stall on it later."""
    STEP, HEADING = "Network", "Downloading nixpkgs"

    def body(self):
        yield Static("Fetching nixpkgs and the other sources this config is pinned to (about 50 MB)…",
                     id="dl-text", classes="muted")
        yield LoadingIndicator()
        with Horizontal(classes="buttons hidden", id="dl-failed"):
            yield Button("Try again", variant="primary", id="retry")
            yield Button("Continue anyway", id="skip")

    def on_mount(self) -> None:
        self.fetch()

    @work(exclusive=True)
    async def fetch(self) -> None:
        self.query_one("#dl-failed").add_class("hidden")
        self.query_one(LoadingIndicator).remove_class("hidden")
        restarted = bool(os.environ.get("OS_INSTALL_RESTARTED"))  # then GitHub's config is in CFG already
        # The real store path: Nix won't read a flake through the /etc/static symlink in pure mode
        ref = str(CFG) if restarted else "path:" + os.path.realpath("/etc/os-repo")
        rc, output = await run("nix", "flake", "archive", ref, check=False)
        if rc == 0:
            self.next()
            return
        self.query_one("#dl-text", Static).update(f"[red]Download failed:[/red] {(output.splitlines() or [''])[-1]}")
        self.query_one(LoadingIndicator).add_class("hidden")
        self.query_one("#dl-failed").remove_class("hidden")

    def next(self) -> None:
        if os.environ.get("OS_INSTALL_RESTARTED"):
            self.notify("Restarted with the latest config from GitHub", title="Config")
            self.app.to_questions()
        else:
            self.app.switch_screen(ConfigScreen())

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "retry":
            self.fetch()
        else:
            self.next()


class WifiPassword(ModalScreen):
    BINDINGS = [("escape", "dismiss(False)", "Cancel")]

    def __init__(self, ssid: str, secured: bool) -> None:
        super().__init__()
        self.ssid, self.secured = ssid, secured

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label(f"[b]Connect to {self.ssid}[/b]")
            if self.secured:
                yield Input(placeholder="Wi-Fi password", password=True, id="wifi-pw")
                yield Checkbox("Show password", id="show-pw")
            yield Static("", id="wifi-status", classes="muted")
            with Horizontal(classes="buttons"):
                yield Button("Cancel", id="cancel")
                yield Button("Connect", variant="primary", id="connect")

    def on_mount(self) -> None:
        if not self.secured:
            self.connect()

    def on_input_submitted(self) -> None:
        self.connect()

    def on_checkbox_changed(self, event: Checkbox.Changed) -> None:
        self.query_one("#wifi-pw", Input).password = not event.value

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(False)
        else:
            self.connect()

    @work(exclusive=True)
    async def connect(self) -> None:
        status = self.query_one("#wifi-status", Static)
        status.update("Connecting…")
        self.query_one("#connect", Button).disabled = True
        args = ["password", self.query_one("#wifi-pw", Input).value] if self.secured else []
        rc, output = await run("nmcli", "dev", "wifi", "connect", self.ssid, *args, check=False)
        if rc == 0:
            await run("nm-online", "-q", "-t", "15", check=False)
        if rc == 0 and await online():
            self.dismiss(True)
            return
        status.update(f"[red]Couldn't connect:[/red] {(output.splitlines() or ['no internet'])[-1]}")
        self.query_one("#connect", Button).disabled = False


class WifiScreen(Step):
    STEP, HEADING = "Network", "No internet connection"

    def body(self):
        yield Static("Choose a Wi-Fi network, or plug in a cable and press [b]Rescan[/b].", classes="muted")
        yield OptionList(id="wifi")
        with Horizontal(classes="buttons"):
            yield Button("Rescan", id="rescan")
            yield Button("Hidden network / other settings…", id="nmtui")

    def on_mount(self) -> None:
        self.networks: dict[str, str] = {}
        self.scan()

    @work(exclusive=True)
    async def scan(self) -> None:
        wifi = self.query_one("#wifi", OptionList)
        wifi.clear_options()
        wifi.add_option(Option("[dim]Scanning…[/dim]", disabled=True))
        if await online():  # a cable may have been plugged in
            self.app.after_network()
            return
        _, output = await run("nmcli", "-t", "-e", "no", "-f", "SIGNAL,SECURITY,SSID", "dev", "wifi", "list",
                              "--rescan", "yes", check=False)
        best: dict[str, tuple[int, str]] = {}
        for line in output.splitlines():
            sig, _, rest = line.partition(":")
            sec, _, ssid = rest.partition(":")  # SSID last: it may contain ':'
            if ssid and sig.isdigit() and int(sig) > best.get(ssid, (-1, ""))[0]:
                best[ssid] = (int(sig), sec)
        self.networks = {ssid: sec for ssid, (_, sec) in best.items()}
        wifi.clear_options()
        for ssid, (sig, sec) in sorted(best.items(), key=lambda kv: -kv[1][0]):
            wifi.add_option(Option(f"{bars(sig)}  {ssid:<28} [dim]{sec or 'open'}[/dim]", id=ssid))
        if not best:
            wifi.add_option(Option("[dim]No Wi-Fi networks found[/dim]", disabled=True))

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        ssid = event.option.id
        self.app.push_screen(WifiPassword(ssid, bool(self.networks.get(ssid))),
                             lambda ok: self.app.after_network() if ok else None)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "nmtui":
            with self.app.suspend():
                subprocess.run(["nmtui"])
        self.scan()


# ------------------------------------------------------------------ config
class ConfigScreen(Step):
    STEP, HEADING = "Config", "Checking for a newer config"

    def body(self):
        yield Static("Comparing this USB stick's config with GitHub…", id="config-text", classes="muted")
        yield LoadingIndicator()

    def on_mount(self) -> None:
        self.prepare()

    @work(exclusive=True)
    async def prepare(self) -> None:
        """Rebuild the ISO's copy of the repo as a git checkout on top of the commit it was built from, so history
        matches GitHub and the host can be pushed later. Then offer GitHub's latest if it differs."""
        bundled = Path("/etc/os-repo-rev").read_text().strip()
        base = bundled.removesuffix("-dirty")
        shutil.rmtree(CFG, ignore_errors=True)
        await run("git", "init", "-q", "-b", "main", CFG)
        git = lambda *a, **kw: run("git", "-C", CFG, *a, **kw)  # noqa: E731
        await git("remote", "add", "origin", REPO)
        is_online = (await git("fetch", "-q", "origin", "main", check=False))[0] == 0
        if is_online and (await git("cat-file", "-e", f"{base}^{{commit}}", check=False))[0] == 0:
            await git("checkout", "-q", "-B", "main", base)
        elif is_online:
            await git("checkout", "-q", "-B", "main", "origin/main")  # ISO built from a commit never pushed
        await run("rsync", "-a", "--delete", "--exclude=.git", "--chmod=u+w", "/etc/os-repo/", f"{CFG}/")
        if (await git("rev-parse", "-q", "--verify", "HEAD", check=False))[0]:  # offline: flakes need a commit
            await git("add", "-A")
            await git("-c", "user.name=os-install", "-c", "user.email=os-install@localhost", "commit", "-q",
                      "-m", f"ISO snapshot {bundled}")
        if not is_online:
            self.notify("Couldn't reach GitHub, using this USB stick's config.", title="Config")
            self.app.to_questions()
            return
        await git("add", "-A")  # include new files in the comparison, then unstage
        same = (await git("diff", "--cached", "--quiet", "origin/main", check=False))[0] == 0
        await git("reset", "-q")
        if same:
            self.app.to_questions()
            return
        rc, ahead = await git("rev-list", "--count", f"{base}..origin/main", check=False)
        _, latest = await git("log", "-1", "--format=[b]%h[/b]  %s [dim](%cr)[/dim]", "origin/main")
        mine = f"[b]{bundled[:7]}[/b]" + ("  [dim](+ uncommitted changes)[/dim]" if bundled.endswith("-dirty") else "")
        github_ahead = rc != 0 or ahead.strip() != "0"  # unknown counts as ahead
        self.heading("A newer config is on GitHub" if github_ahead else "This USB has changes that aren't on GitHub")
        self.query_one("#config-text", Static).update("The config on GitHub differs from the one on this USB stick.")
        self.query_one(LoadingIndicator).remove()
        await self.query_one("#body").mount_all([
            Static(f"[dim]This USB [/dim]  {mine}\n"
                   f"[dim]GitHub   [/dim]  {latest}  [dim]{ahead if rc == 0 else '?'} new commit(s)[/dim]",
                   classes="panel"),
            # Highlight whichever is newer
            Horizontal(Button("Keep this USB's", variant="default" if github_ahead else "primary", id="keep"),
                       Button("Use GitHub's latest", variant="primary" if github_ahead else "default", id="latest"),
                       classes="buttons")])

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "latest":
            await run("git", "-C", CFG, "checkout", "-q", "-f", "-B", "main", "origin/main")
            await run("git", "-C", CFG, "clean", "-qfdx")
            self.app.exit("restart")  # main() restarts with GitHub's installer, which may differ too
        else:
            self.app.to_questions()


# ------------------------------------------------------------------ questions
class HostnameScreen(Question):
    STEP, HEADING = "Hostname", "Name this machine"
    BINDINGS = [Binding("escape", "back", "Back", show=False)]  # nothing before this to go back to

    def body(self):
        yield Static("Lowercase letters, digits and dashes. It becomes [b]hosts/<name>[/b] in the repo.",
                     classes="muted")
        yield Input(placeholder="e.g. xanathar", id="hostname", value=self.app.state.get("hostname", ""))
        yield Label("", id="hostname-error", classes="error")
        with Horizontal(classes="buttons"):
            yield Button("Next", variant="primary", id="next", disabled=True)

    def on_input_changed(self, event: Input.Changed) -> None:
        name, error = event.value, ""
        if name and not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
            error = "Use lowercase letters, digits and dashes."
        elif name and (CFG / "hosts" / name).exists():
            error = f"hosts/{name} already exists."
        self.query_one("#hostname-error", Label).update(error)
        self.query_one("#next", Button).disabled = bool(error) or not name
        if name and not error:
            self.state["hostname"] = name

    def on_input_submitted(self) -> None:
        if not self.query_one("#next", Button).disabled:
            self.app.push_screen(DiskScreen())

    def on_button_pressed(self) -> None:
        self.app.push_screen(DiskScreen())


class DiskScreen(Question):
    STEP, HEADING = "Disk", "Where should NixOS go?"

    def body(self):
        disks = list_disks()
        self.disks = {dev: (model, size) for dev, model, size in disks}
        yield Static("[b red]The disk you choose will be completely erased.[/]  The USB stick isn't listed.")
        if disks:
            yield OptionList(*[Option(f"[b]{model}[/b]  [dim]{size}[/dim]\n[dim]{dev}[/dim]", id=dev)
                               for dev, model, size in disks], id="disks")
        else:
            yield Static("[red]No disks found in /dev/disk/by-id.[/red]", classes="panel")

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.state["disk"] = event.option.id
        self.state["disk_desc"] = " ".join(self.disks[event.option.id])
        self.app.push_screen(DesktopScreen())


class DesktopScreen(Question):
    STEP, HEADING = "Desktop", "Pick a desktop"

    def body(self):
        yield OptionList(
            Option("[b]KDE Plasma[/b]\n[dim]Plasma 6 and SDDM. Familiar, gaming-friendly (the Bazzite feel).[/dim]",
                   id="kde"),
            Option("[b]niri + DankMaterialShell[/b]\n[dim]Scrollable tiling with the DMS bar, launcher and "
                   "greeter (the Zirconium feel).[/dim]", id="niri"),
            id="desktop")

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.state["desktop"] = event.option.id
        self.app.push_screen(WallpapersScreen())


class WallpapersScreen(Question):
    STEP, HEADING = "Wallpapers", "Pick a wallpaper set"

    def body(self):
        # The sets are the folders in wallpapers/ (my.wallpapers in modules/options/wallpapers.nix)
        how = ("Plasma shows a new one every hour, spread across all your monitors."
               if self.state["desktop"] == "kde" else
               "DMS's wallpaper picker and automatic cycling start in this set's folder.")
        yield Static(f"{how} Change it later with [b]os wallpapers <set>[/b].", classes="muted")
        sets = sorted(d for d in (CFG / "wallpapers").iterdir() if d.is_dir())
        yield OptionList(*(Option(f"[b]{d.name}[/b]\n[dim]{n} wallpapers[/dim]" if n else
                                  f"[b]{d.name}[/b]\n[dim]empty for now[/dim]", id=d.name)
                           for d in sets for n in [sum(1 for f in d.iterdir() if not f.name.startswith("."))]),
                         id="wallpapers")

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.state["wallpapers"] = event.option.id
        self.app.push_screen(OptionsScreen())


class OptionsScreen(Question):
    STEP, HEADING = "Options", "Extras for this machine"

    def body(self):
        # The list comes from the config itself: every on/off my.* option in modules/options (flake.nix: installer)
        yield Static("Space toggles. Change these later in hosts/<name>.", classes="muted")
        yield LoadingIndicator()
        yield SelectionList[str](id="options", classes="hidden")
        yield Static("", id="chosen")
        with Horizontal(classes="buttons"):
            yield Button("Next", variant="primary", id="next", disabled=True)

    def on_mount(self) -> None:
        self.load()

    @work(exclusive=True)
    async def load(self) -> None:
        if "all_options" not in self.state:
            rc, output = await self.app.options_task
            try:
                self.state["all_options"] = json.loads(output.splitlines()[-1]) if rc == 0 else {}
            except (ValueError, IndexError):
                self.state["all_options"] = {}
            if not self.state["all_options"]:
                self.notify("Couldn't read the options from the config; continuing without any.",
                            title="Options", severity="error")
        options = self.query_one("#options", SelectionList)
        options.add_options([(label, name, name in self.state["options"])
                             for name, label in sorted(self.state["all_options"].items())])
        self.query_one(LoadingIndicator).remove()
        options.remove_class("hidden")
        options.focus()
        self.query_one("#next", Button).disabled = False
        self.show_chosen()

    def show_chosen(self) -> None:
        options = self.query_one("#options", SelectionList)
        labels = [self.state["all_options"][name] for name in options.selected]
        self.query_one("#chosen", Static).update(
            "Selected: " + ("[b green]" + ", ".join(labels) + "[/]" if labels else "[dim]nothing[/dim]"))

    def on_selection_list_selected_changed(self) -> None:
        self.show_chosen()

    def on_button_pressed(self) -> None:
        self.state["options"] = list(self.query_one("#options", SelectionList).selected)
        self.app.push_screen(GitHubScreen())


class GitHubScreen(Question):
    STEP, HEADING = "GitHub", "Set up GitHub now?"

    def body(self):
        yield Static("Adds this machine's SSH key to your GitHub account and pushes [b]hosts/<name>[/b] when the "
                     "install finishes. You log in now, so the rest can run unattended.", classes="muted")
        with Horizontal(classes="buttons"):
            yield Button("Skip", id="skip")
            yield Button("Log in to GitHub", variant="primary", id="login")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.state["github"] = False
        self.app.push_screen(GitHubLoginScreen() if event.button.id == "login" else PasswordScreen())


class GitHubLoginScreen(Question):
    STEP, HEADING = "GitHub", "Log in to GitHub"
    LIFETIME = 900  # device codes expire after 15 minutes

    def body(self):
        yield Static("On your phone or another computer, open [b]github.com/login/device[/b] and enter:",
                     classes="muted")
        yield Static("…", id="code")
        yield Label("Requesting a code…", id="expires", classes="muted")
        yield ProgressBar(total=self.LIFETIME, show_eta=False, show_percentage=False, id="countdown")
        with Horizontal(classes="buttons"):
            yield Button("Skip GitHub", id="skip")
            yield Button("Try again", id="retry", classes="hidden")

    def on_mount(self) -> None:
        self.proc = None
        self.set_interval(1, self.tick)
        self.login()

    def tick(self) -> None:
        if getattr(self, "left", None) is None or self.left <= 0:
            return
        self.left -= 1
        self.query_one("#countdown", ProgressBar).update(progress=self.left)
        self.query_one("#expires", Label).update(
            f"Waiting for approval…  code expires in {self.left // 60}:{self.left % 60:02d}")

    @work(exclusive=True)
    async def login(self) -> None:
        self.left = None
        self.query_one("#retry").add_class("hidden")
        # stdin not a terminal: gh skips its "Press Enter to open a browser" prompt (there's no browser here)
        cmd = ["gh", "auth", "login", "-h", "github.com", "-p", "ssh", "-w", "--skip-ssh-key", "-s",
               "admin:public_key"]
        log("$ " + " ".join(cmd))
        proc = self.proc = await asyncio.create_subprocess_exec(*cmd, env=ENV, stdin=asyncio.subprocess.DEVNULL,
                                                                stdout=asyncio.subprocess.PIPE,
                                                                stderr=asyncio.subprocess.STDOUT)
        lines = []
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip()
            lines.append(line)
            log(line)
            code = GH_CODE.search(line)
            if code and self.left is None:
                self.query_one("#code", Static).update(code.group())
                self.left = self.LIFETIME
        rc = await proc.wait()
        if self.proc is None:  # skipped
            return
        if rc == 0:
            await run("gh", "auth", "setup-git", check=False)
            self.state["github"] = True
            self.notify("Logged in to GitHub", title="GitHub")
            self.app.push_screen(PasswordScreen())
            return
        self.left = None
        self.query_one("#expires", Label).update(f"[red]Login failed:[/red] {(lines or ['no output'])[-1]}")
        self.query_one("#retry").remove_class("hidden")

    def stop(self) -> None:
        proc, self.proc = self.proc, None
        if proc and proc.returncode is None:
            proc.terminate()

    def action_back(self) -> None:
        self.stop()
        super().action_back()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "retry":
            self.login()
            return
        self.stop()
        self.state["github"] = False
        self.app.push_screen(PasswordScreen())


class PasswordScreen(Question):
    STEP, HEADING = "Password", f"Password for {USER}"

    def body(self):
        yield Input(placeholder="Password", password=True, id="pw1")
        yield Input(placeholder="Repeat password", password=True, id="pw2")
        yield Label("", id="pw-error", classes="error")
        with Horizontal(classes="buttons"):
            yield Button("Next", variant="primary", id="next", disabled=True)

    def on_input_changed(self) -> None:
        p1, p2 = (self.query_one(f"#pw{i}", Input).value for i in (1, 2))
        self.query_one("#pw-error", Label).update("Passwords don't match." if p2 and p1 != p2 else "")
        self.query_one("#next", Button).disabled = not p1 or p1 != p2

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "pw1":
            self.query_one("#pw2", Input).focus()
        elif not self.query_one("#next", Button).disabled:
            self.on_button_pressed()

    def on_button_pressed(self) -> None:
        self.state["password"] = self.query_one("#pw1", Input).value
        self.app.push_screen(SummaryScreen())


class SummaryScreen(Question):
    STEP, HEADING = "Summary", "Ready to install"

    def body(self):
        s = self.state
        github = f"logged in, will push hosts/{s['hostname']}" if s["github"] else "skipped"
        desktop = s["desktop"] + (f"  [dim]wallpapers:[/dim] {s['wallpapers']}" if s.get("wallpapers") else "")
        yield Static(
            f"[dim]Hostname[/dim]   [b]{s['hostname']}[/b]\n"
            f"[dim]Disk    [/dim]   [b]{s['disk_desc']}[/b]  [dim]{s['disk']}[/dim]\n"
            f"[dim]Desktop [/dim]   {desktop}\n"
            f"[dim]Options [/dim]   {', '.join(s['options']) or 'none'}\n"
            f"[dim]GitHub  [/dim]   {github}\n"
            f"[dim]NixOS   [/dim]   {self.app.release}",
            classes="panel")
        yield Static(f"[b red]Everything on {s['disk_desc']} will be erased.[/]  "
                     f"Type [b]{s['hostname']}[/b] to confirm:")
        yield Input(placeholder=s["hostname"], id="confirm")
        with Horizontal(classes="buttons"):
            yield Button("Erase disk and install", variant="error", id="go", disabled=True)

    def on_input_changed(self, event: Input.Changed) -> None:
        self.query_one("#go", Button).disabled = event.value != self.state["hostname"]

    def on_input_submitted(self) -> None:
        if not self.query_one("#go", Button).disabled:
            self.on_button_pressed()

    def on_button_pressed(self) -> None:
        self.app.switch_screen(InstallScreen())  # no going back from here


# ------------------------------------------------------------------ install
class InstallScreen(Step):
    STEP, HEADING = "Install", "Installing"

    def body(self):
        with Horizontal(id="install"):
            yield Static("", id="phases")
            with Vertical():
                yield ProgressBar(total=100, show_eta=False, id="overall")
                yield Static("Starting…", id="current")
                yield RichLog(id="log", max_lines=2000)
                with Horizontal(classes="buttons hidden", id="failed"):
                    yield Button("Exit to shell", variant="error", id="exit")

    def on_mount(self) -> None:
        self.heading(f"Installing {self.state['hostname']}")
        self.phase, self.failed = 0, False
        self.show_phases()
        self.install()

    def show_phases(self) -> None:
        lines = []
        for i, name in enumerate(PHASES):
            if i < self.phase:
                lines.append(f"[green]✓[/green] {name}")
            elif i == self.phase:
                lines.append(f"[b red]✗ {name}[/]" if self.failed else f"[b yellow]●[/] [b]{name}[/b]")
            else:
                lines.append(f"[dim]○ {name}[/dim]")
        self.query_one("#phases", Static).update("\n".join(lines))

    def progress(self, pct: int, text: str, phase: int | None = None) -> None:
        if phase is not None:
            self.phase = phase
            self.show_phases()
        self.query_one("#overall", ProgressBar).update(progress=pct)
        self.query_one("#current", Static).update(text)

    def show(self, line: str) -> None:
        self.query_one("#log", RichLog).write(line)

    async def sh(self, *cmd, **kw):
        return await run(*cmd, on_line=kw.pop("on_line", self.show), **kw)

    def write_host(self) -> None:
        s = self.state
        host = CFG / "hosts" / s["hostname"]
        host.mkdir(parents=True)
        options = "\n".join(f"  my.{name} = {str(name in s['options']).lower()};"
                            for name in sorted(s.get("all_options", {})))
        wallpapers = f'\n  my.wallpapers = "{s["wallpapers"]}";' if s.get("wallpapers") else ""
        (host / "default.nix").write_text(f"""{{
  imports = [ ./hardware-configuration.nix ];
  disko.devices = (import ../../disko.nix {{ device = "{s['disk']}"; }}).disko.devices;

  my.desktop = "{s['desktop']}";{wallpapers}
{options}

  system.stateVersion = "{self.app.release}"; # release this machine was installed with; never change it
}}
""")

    @work(exclusive=True)
    async def install(self) -> None:
        s = self.state
        name = s["hostname"]
        try:
            self.progress(1, f"Partitioning {s['disk_desc']}…", 0)
            await self.sh("disko", "--mode", "destroy,format,mount", "--yes-wipe-all-disks", "--argstr", "device",
                          s["disk"], "disko.nix", cwd=CFG)

            self.progress(4, f"Writing hosts/{name}…", 1)
            self.write_host()
            # disko owns the filesystems; stdout only (warnings would corrupt the file)
            hw = await asyncio.to_thread(subprocess.run, ["nixos-generate-config", "--root", "/mnt",
                                         "--no-filesystems", "--show-hardware-config"],
                                         capture_output=True, text=True, check=True)
            (CFG / "hosts" / name / "hardware-configuration.nix").write_text(hw.stdout)
            await self.sh("git", "-C", CFG, "add", f"hosts/{name}")  # flakes only see tracked files
            Path("/mnt/etc").mkdir(parents=True, exist_ok=True)
            await self.sh("cp", "-a", CFG, "/mnt/etc/nixos")

            # Build the system into /mnt ourselves (what nixos-install would do) so downloads drive the bar
            self.progress(6, "Working out what to download (about a minute)…", 2)
            ref = f"/mnt/etc/nixos#nixosConfigurations.{name}.config.system.build.toplevel"
            nix = ["nix", "build", "--store", "/mnt", "--extra-substituters", "auto?trusted=1"]
            _, dry = await self.sh(*nix, "--dry-run", ref)
            total = max(1, sum(1 for line in dry.splitlines() if line.strip().startswith("/nix/store/")))
            done = 0

            def on_line(line: str) -> None:
                nonlocal done
                self.show(line)
                if line.startswith(("copying path '", "building '")):
                    done += 1
                    pkg = re.sub(r"^/nix/store/[a-z0-9]+-|\.drv$", "", line.split("'")[1])
                    self.progress(min(90, 8 + done * 82 // total),
                                  f"Downloading packages  [b]{done}[/b] of {total}   [dim]{pkg}[/dim]", 3)

            self.progress(8, f"Downloading packages  0 of {total}", 3)
            await self.sh(*nix, "--out-link", "/tmp/system", ref, on_line=on_line)
            system = os.readlink("/tmp/system")

            self.progress(91, "Installing the bootloader…", 4)
            await self.sh("nixos-install", "--system", system, "--no-root-passwd", "--no-channel-copy")

            self.progress(95, "Setting the password…", 5)
            await self.sh("nixos-enter", "--root", "/mnt", "-c", "chpasswd", input=f"{USER}:{s['password']}\n")
            s.pop("password")

            self.progress(97, "Adding the SSH key to GitHub and pushing…", 6)
            if s["github"]:
                try:
                    await self.github_setup()
                except CommandError as e:  # never fail the install here
                    s["github_error"] = str(e)
                    self.show(f"GitHub step failed: {e}")

            self.progress(99, "Finishing up…", 7)
            # Numeric ids (uid fixed in modules/common.nix, gid 100 = users): the ISO has no user called justin
            await self.sh("mkdir", "-p", f"/mnt/home/{USER}")
            await self.sh("chown", "-R", "1000:100", f"/mnt/home/{USER}", "/mnt/etc/nixos")
            if os.stat("/mnt/etc/nixos").st_uid != 1000:
                raise CommandError(f"Could not hand /etc/nixos to {USER}")
            # Wi-Fi networks joined on the USB stick (NetworkManager saves them as files) work after reboot too
            for conn in Path("/etc/NetworkManager/system-connections").glob("*.nmconnection"):
                dest = Path("/mnt/etc/NetworkManager/system-connections") / conn.name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(conn, dest)
                dest.chmod(0o600)  # holds the Wi-Fi password; NetworkManager ignores files others can read
                self.show(f"Copied Wi-Fi network {conn.stem}")
            self.progress(100, "Done", len(PHASES))
            self.app.switch_screen(DoneScreen())
        except Exception as e:  # show it on screen and keep the log visible
            self.failed = True
            self.show_phases()
            self.heading("[red]Installation failed[/red]")
            self.query_one("#current", Static).update(f"[red]{e}[/red]\n[dim]Full log: {LOG}[/dim]")
            self.query_one("#failed").remove_class("hidden")
            log(f"FAILED: {e!r}")

    async def github_setup(self) -> None:
        s = self.state
        home = Path(f"/mnt/home/{USER}")
        (home / ".ssh").mkdir(parents=True, exist_ok=True)
        (home / ".ssh").chmod(0o700)
        (home / ".config").mkdir(parents=True, exist_ok=True)
        key = home / ".ssh" / "id_ed25519"
        await self.sh("ssh-keygen", "-t", "ed25519", "-N", "", "-C", f"{USER}@{s['hostname']}", "-f", key)
        await self.sh("gh", "ssh-key", "add", f"{key}.pub", "--title", s["hostname"])
        login = out("gh", "api", "user", "--jq", ".login")
        uid = out("gh", "api", "user", "--jq", ".id")
        who = ["-c", f"user.name={login}", "-c", f"user.email={uid}+{login}@users.noreply.github.com"]
        repo = "/mnt/etc/nixos"
        await self.sh("git", "-C", repo, *who, "commit", "-m", f"Add host {s['hostname']}")
        # an ISO built from uncommitted changes leaves them unstaged
        await self.sh("git", "-C", repo, *who, "pull", "--rebase", "--autostash")
        await self.sh("git", "-C", repo, "push")
        await self.sh("git", "-C", repo, "remote", "set-url", "origin", f"git@github.com:{OWNER_REPO}.git")
        shutil.copytree(Path.home() / ".config" / "gh", home / ".config" / "gh", dirs_exist_ok=True)

    def on_button_pressed(self) -> None:
        self.app.exit()


class DoneScreen(Step):
    STEP, HEADING = "Done", "Installed"

    def body(self):
        s = self.state
        lines = [f"[b green]✓  {s['hostname']} is installed.[/]", "", "Remove the USB stick, then reboot."]
        if s.get("github_error"):
            lines += ["", "[yellow]The GitHub step failed[/yellow] (details in the log). After rebooting:",
                      "  ssh-keygen -t ed25519 && gh auth login -p ssh",
                      f"  cd /etc/nixos && git commit -m 'Add host {s['hostname']}' && git pull --rebase && git push",
                      f"  git remote set-url origin git@github.com:{OWNER_REPO}.git"]
        elif s["github"]:
            lines.append(f"hosts/{s['hostname']} was pushed to GitHub; this machine's SSH key was added.")
        if "meshagent" in s["options"]:
            lines += ["", "After logging in, enroll MeshCentral with:  [b]sudo meshagent-enroll[/b]"]
        yield Static("\n".join(lines), classes="panel")
        with Horizontal(classes="buttons"):
            yield Button("Exit to shell", id="shell")
            yield Button("Reboot", variant="success", id="reboot")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.app.exit(event.button.id)


# ------------------------------------------------------------------ app
class Installer(App):
    ENABLE_COMMAND_PALETTE = False
    TITLE = "NixOS installer"
    SUB_TITLE = OWNER_REPO
    CSS = """
    #sidebar { width: 20; padding: 1 2; border-right: tall $panel; height: 100%; }
    #body { padding: 1 3; }
    .heading { text-style: bold; color: $accent; margin-bottom: 1; }
    .muted { color: $text-muted; margin-bottom: 1; }
    .error { color: $error; height: 1; }
    .panel { border: round $primary; padding: 1 2; margin: 1 0; height: auto; }
    .buttons { height: auto; margin-top: 1; }
    .buttons Button { margin-right: 2; width: auto; min-width: 12; }
    /* Textual's focused button flips its label to white (reverse); a border marks focus instead */
    Button:focus { text-style: bold; border: tall $accent; }
    /* Ticked = green box, unticked = empty box (Textual draws a dim X in both states by default) */
    SelectionList > .selection-list--button, SelectionList > .selection-list--button-highlighted {
        color: $panel; background: $panel; }
    SelectionList > .selection-list--button-selected, SelectionList > .selection-list--button-selected-highlighted {
        color: $text; background: $success; text-style: bold; }
    Checkbox > .toggle--button { color: $panel; background: $panel; }
    Checkbox.-on > .toggle--button { color: $text; background: $success; text-style: bold; }
    Checkbox:focus > .toggle--label { color: $text; background: transparent; text-style: bold; }  /* border marks focus */
    #chosen { margin-bottom: 1; }
    #show-pw { margin-bottom: 1; }
    .hidden { display: none; }
    OptionList, SelectionList { height: auto; max-height: 14; margin-bottom: 1; }
    Input { margin-bottom: 1; max-width: 60; }
    LoadingIndicator { height: 3; }
    #code { width: auto; text-style: bold; color: $accent; border: heavy $accent; padding: 1 6; margin: 1 0; }
    #countdown { margin-bottom: 1; }
    #install { height: 1fr; }
    #phases { width: 26; padding-right: 2; }
    #overall { margin-bottom: 1; }
    #current { margin-bottom: 1; height: auto; }
    #log { border: round $panel; height: 1fr; }
    WifiPassword { align: center middle; }
    #dialog { width: 60; height: auto; border: thick $accent; background: $surface; padding: 1 2; }
    """

    def __init__(self) -> None:
        super().__init__()
        self.state: dict = {"options": [], "github": False}
        self.release = ".".join(out("nixos-version").split(".")[:2])

    def on_mount(self) -> None:
        log(f"=== os-install (restarted={bool(os.environ.get('OS_INSTALL_RESTARTED'))})")
        self.push_screen(StartScreen())

    def after_network(self) -> None:
        self.switch_screen(DownloadScreen())

    def to_questions(self) -> None:
        """Config is final: make it fully visible to Nix, start reading its options, ask the questions."""
        # Files the ISO added on top of its commit are untracked, and flakes ignore untracked files.
        # Intent-to-add makes them visible without staging them for the host commit.
        out("git", "-C", str(CFG), "add", "--intent-to-add", ".")
        self.options_task = asyncio.create_task(
            run("nix", "eval", "--json", f"{CFG}#installer.options", check=False))
        self.switch_screen(HostnameScreen())


def main() -> None:
    result = Installer().run()
    if result == "restart":  # run GitHub's installer (this one if GitHub's predates install.py)
        script = CFG / "install.py" if (CFG / "install.py").exists() else Path(__file__)
        os.execve(sys.executable, [sys.executable, str(script)], {**os.environ, "OS_INSTALL_RESTARTED": "1"})
    if result == "reboot":
        subprocess.run(["systemctl", "reboot"])
    if result is None or result == "shell":
        print(f"Installer stopped. Log: {LOG}. Run os-install to start again.")


if __name__ == "__main__":
    main()
