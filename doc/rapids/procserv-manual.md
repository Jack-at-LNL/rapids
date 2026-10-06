# RAPIDS procServ Manual

## 1. What this role does

The `rapids_procserv` role installs [procServ](https://github.com/ralphlange/procServ)
and its companion tool `manage-procs` — the EPICS community's own systemd
integration for procServ — so that any IOC can be run as a properly
supervised, reboot-surviving systemd service, with telnet console access
for the standard EPICS "attach to the IOC shell" workflow.

**RAPIDS does not create, own, or manage the lifecycle of any production
IOC.** This role's job stops at "the tool works correctly here." Once
installed, you create and manage your own IOCs exactly as you would on any
EPICS workstation that happens to have procServ installed — using
`manage-procs` directly, by hand or from your own scripts.

Enable it with:

```yaml
rapids_procserv: true
rapids_procserv_selfcheck: true   # default; see section 4
```

## 2. Why procServ is installed to `/usr/local`, not `/opt/epics-tools`

Every other RAPIDS-installed tool lives under `/opt/epics-tools/`. procServ
is the one deliberate exception, and the reason is load-bearing, not
stylistic: `manage-procs`' systemd-unit generator locates the
`procServ-launcher` binary via a plain `PATH` search, both when you run
`manage-procs add` and again, independently, every time systemd itself
runs the generator at boot. `/usr/local/bin` is already on systemd's and
`sudo`'s default `PATH` on every target OS RAPIDS supports; relocating
procServ's prefix breaks that search silently; the generated unit's
`ExecStart` becomes the literal string `None` instead of a real path, and
the instance simply never starts — with no error at `manage-procs add`
time to warn you.

If you ever find yourself tempted to move this to `/opt/epics-tools` for
consistency, don't: this was tried, confirmed broken, and reverted during
RAPIDS development.

### 2.1 A competing package-manager install

Some distributions (EPEL, in particular) ship a `procServ` package. It
does **not** include `procServUtils`/`manage-procs` — the systemd
integration only exists when procServ is built with `--with-systemd-utils`,
which no distribution package does. If such a package is also installed
(typically at `/usr/bin/procServ`), the role detects it and prints a
warning, but takes no action: removing a package you may have installed
deliberately is not this role's decision. RAPIDS always uses the full path
to its own build (`/usr/local/bin/...`), so the coexistence is harmless to
RAPIDS itself — but if you type a bare `procServ` or `manage-procs` at an
interactive shell, run `which procServ` first to see which one your `PATH`
actually resolves.

## 3. What gets installed, and how

- procServ 2.8.0 is built from source: `./configure --with-systemd-utils`,
  `make`, `make install`.
- A confirmed defect in this version's `setup.py`
  (`os.chmod(file, 0755)`, Python-2-only syntax) is patched automatically
  before building — every build of this version needs this fix.
- The systemd generator `make install` produces is placed under
  `/usr/local/lib/systemd/system-generators/`, which is **not** one of the
  paths systemd itself scans for generators at boot. The role symlinks it
  into `/usr/lib/systemd/system-generators/` — without this, no IOC you
  create would survive a reboot, with no error anywhere to tell you why.
- The role is idempotent across version changes: if the installed
  `procServ`/`manage-procs` don't match `rapids_procserv_version`, or
  either is missing, it cleans up the previous install's files and
  rebuilds. Re-running `update.sh` with no version change leaves a working
  install untouched.

Key variables (`ansible/roles/rapids_procserv/defaults/main.yml`):

| Variable | Default | Meaning |
|---|---|---|
| `rapids_procserv_version` | `2.8.0` | procServ release to build |
| `rapids_procserv_prefix` | `/usr/local` | install prefix — see section 2 |
| `rapids_procserv_selfcheck` | `true` | run the self-check at install time |
| `rapids_procserv_selfcheck_port` | `4051` | telnet port for the self-check instance |
| `rapids_procserv_iocs_dir` | `/opt/epics/iocs` | where your own IOCs conventionally live — see section 5 |
| `rapids_procserv_healthcheck_dir` | `/opt/epics-tools/procserv/scripts` | where the healthcheck script is installed |

## 4. The self-check, and the standalone healthcheck script

At install time (and whenever you re-run `update.sh`), the role installs
and runs `rapids_procserv_healthcheck.sh`. It stays installed afterward —
you can re-run it yourself at any time:

```bash
bash /opt/epics-tools/procserv/scripts/rapids_procserv_healthcheck.sh
```

It reports four sections, each independently, and writes a timestamped
report to `~/procserv-tests-<date>.txt`:

- **P1** — procServ and `manage-procs` are installed and resolvable
  (including the exact `PATH`/`procServ-launcher` resolution problem
  described in section 2).
- **P2** — the systemd generator is correctly symlinked.
- **P3** — a transient, self-disabling sine-wave IOC is added with
  `manage-procs`, confirmed reachable over the network with a real
  `caget` (not just `systemctl status`), then stopped and disabled. This
  is the only step that genuinely proves the whole chain works end to
  end — the unit stays on disk afterward as visible proof the check ran,
  under the name `selfcheck` / PV prefix `...:procserv-selfcheck:...`.
  Its working directory is `/opt/epics-tools/procserv/selfcheck/`,
  deliberately **not** inside `rapids_procserv_iocs_dir` — see section 5.
- **P4** — a **read-only** report of any instance you have already
  declared under `/etc/procServ.d/*.conf`. This script never starts,
  stops, or modifies anything it finds here; it only reports active/
  enabled status, so a field engineer can see at a glance what's running
  without any risk of disrupting a real production IOC. (The self-check's
  own `selfcheck` instance is listed here too, since its unit genuinely
  sits in that same directory — a note makes clear it's the self-check's
  own artifact, not a separate IOC.)

A failure anywhere **warns loudly but does not halt the install** — the
reasoning being that a broken procServ shouldn't block the rest of a
facility's EPICS stack from installing. Review the warning, and the
report file, before relying on procServ in production.

For non-interactive/manual use, the script reads its scope from the
environment rather than from `local.yml` directly, so it can be re-run
standalone:

```bash
RAPIDS_PROJECT_NAME="MyProject" RAPIDS_INSTANCE_NAME="vm01" \
  bash /opt/epics-tools/procserv/scripts/rapids_procserv_healthcheck.sh
```

Use `PROCSERV_SELFCHECK_PORT=<other>` if port 4051 is already in use on
your box.

## 5. Where your own IOCs go — and why it matters

`rapids_procserv_iocs_dir` defaults to **`/opt/epics/iocs`** — a sibling
of `/opt/epics/base-<version>` and the EPICS modules RAPIDS installs
there, not nested inside `/opt/epics-tools/` (which is reserved for
RAPIDS's own bundled service tooling: Olog, the Archiver Appliance,
Phoebus configuration, procServ itself).

This matches how real EPICS facilities lay out their control systems —
e.g. the EIC collaboration's `/epics/{modules,iocs,apps}`, or SNS/ANL's
`iocTop` sitting alongside `base` and the module pool — rather than
burying a facility's actual control-system application inside a
deployment tool's own directory tree. RAPIDS creates this directory
(owned by `{{ dev_user }}`, since `/opt/epics/` itself is root-owned) but
never writes inside it. It is yours.

## 6. Creating your own production IOC

This is the workflow RAPIDS exists to make possible, not to perform for
you. A minimal example, using the sine-wave `.db` style from the
self-check as a template:

```bash
mkdir -p /opt/epics/iocs/my-ioc
cat > /opt/epics/iocs/my-ioc/my-ioc.db << 'EOF'
record(ai, "MyProject:vm01:temperature") {
    field(SCAN, "1 second")
    field(INP, "@my-device-link")
}
EOF

sudo env PATH="/usr/local/bin:$PATH" PYTHONPATH="/usr/local/lib/python3.9/site-packages" \
  manage-procs --system add \
  -C /opt/epics/iocs/my-ioc \
  -P 4060 \
  -U epics-dev -G epics-dev \
  -A my-ioc \
  $(bash -l -c 'command -v softIocPVX') -S -d my-ioc.db

sudo systemctl enable procserv-my-ioc
```

A few points that cost real debugging time during RAPIDS development,
included here so you don't rediscover them:

- **Always use the full absolute path** to both `manage-procs` and the
  IOC binary (`softIocPVX`, found via `bash -l -c 'command -v
  softIocPVX'` — a plain `which`/`command -v` only works in a login
  shell that has sourced `epics-tools.sh`).
- **`sudo` on this OS does not inherit your shell's `PATH`.** Either
  `sudo env PATH="..." PYTHONPATH="..." manage-procs ...` as above, or
  run as root with a login shell.
- **`manage-procs add -A <name>` automatically prepends `procserv-` to
  the generated systemd unit's name.** Don't include that prefix
  yourself (`-A procserv-my-ioc` produces
  `procserv-procserv-my-ioc.service`) — this has bitten RAPIDS's own
  scripts twice during development.
- **Always pass `-G <group>` explicitly.** The tool's default group,
  `nogroup`, doesn't exist on RHEL-family systems.
- **`manage-procs add` already enables the instance** — the symlink into
  `multi-user.target.wants/` is created by `add` itself, not by a
  separate `systemctl enable`. A plain `systemctl enable` on a
  generator-produced unit (as opposed to the static unit `manage-procs
  add` writes to `/etc/procServ.d/`) fails with "transient or generated."

Lifecycle from here on is standard systemd: `systemctl start|stop|status
procserv-my-ioc`, `telnet localhost 4060` for the procServ console.
`manage-procs --system remove my-ioc` tears it down.

## 7. PV-naming convention

If you set `rapids_instance_name` (see `local.yml.sample`), use it — and
`rapids_project_name` — in your own IOCs' PV names, the same way the
self-check and the Archiver healthcheck do, so that two RAPIDS
installations on the same network never serve colliding PV names.

**Avoid `-` and `:` in both `rapids_project_name` and
`rapids_instance_name`.** The Archiver Appliance's PV-to-path conversion
turns both characters into directory separators on disk — harmless, but
confusing to browse (`"My-Project"` is stored as a nested folder
`My/Project`, not as one name).

## 8. Troubleshooting

**Self-check fails at P3 with "softIocPVX not found"** — this means the
check (or your own manual invocation of `manage-procs`) ran in a non-login
shell; `epics-tools.sh`, which puts `softIocPVX` on `PATH`, is only
sourced in a login shell. Use `bash -l -c 'command -v softIocPVX'`, not a
bare `which`.

**A generated unit's `ExecStart` reads `None`** — `procServ-launcher`
could not be resolved via `PATH` at `manage-procs add` time. Check `which
procServ-launcher`; if empty, confirm `/usr/local/bin` is on the `PATH` of
whatever shell/user ran `manage-procs add` (see section 2 and 6).

**`systemctl enable` fails with "transient or generated"** — you are
trying to enable a unit that only exists because the systemd generator
produced it at boot (under `/run/systemd/generator/`). You need the
*static* unit `manage-procs add` writes to `/etc/procServ.d/`, which it
symlinks into `/etc/systemd/system/` itself — this is what makes
`enable`/`disable` work. If you deleted that symlink by hand, re-run
`manage-procs add` rather than trying to `enable` the generator's output
directly.

**P4 lists an instance I don't recognize** — this is read-only reporting;
nothing here was started or changed by the healthcheck. Check
`/etc/procServ.d/<name>.conf` to see what it actually runs, and
`systemctl status procserv-<name>` for its current state.

## 9. What RAPIDS does *not* do here

No backup/restore mechanism for IOC databases or startup files is
provided — they are your own source-controlled artifacts, same as any
EPICS deployment. No multi-host or NFS-based IOC distribution is set up
(see section 5 for the local directory convention only). RAPIDS does not
inventory, start, or stop your IOCs as part of any future `update.sh` run
— once created, they are entirely yours to manage with `manage-procs`,
`systemctl`, or whatever tooling you build on top.
