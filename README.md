# RAPIDS

**Rapid Automated Production Infrastructure Deployment System** — turn a vanilla Linux box into a complete, production-capable EPICS control system, labeled with your own project's identity, in a few hours.

## Why RAPIDS exists

Large accelerator facilities and national laboratories typically have dedicated controls teams: engineers whose job is building and running the central EPICS control system, day in and day out. That expertise is exactly what makes a production-grade control system possible — and exactly what most beamlines, experiments, and technological plants *don't* have, and don't need full-time.

A beamline or a small experiment needs its own logbook, its own archiver, its own working IOCs — but it rarely needs, and often can't justify, being folded into the central facility's control system. The central team's own system has its own release cycle, its own change-control process, its own priorities — it simply isn't built to be as dynamic and specific as one experiment's actual needs: a private logbook that only matters for a handful of shifts, an archiver scoped to one beamline's own PVs, a control system that one small team can own, understand, and modify without needing to negotiate with anyone else.

The same gap shows up outside beamlines too: a facility's technological plant — cooling, vacuum, access control, anything that benefits from EPICS integration — often needs its own self-contained control system, not a slice of the central one, and often has no dedicated controls engineer to build it by hand.

**RAPIDS exists to close that gap**, and it already does, in production: at INFN Laboratori Nazionali di Legnaro, RAPIDS runs the EPICS control system for **ANTHEM** (the Italian BNCT patient-treatment project) and is in use for the **Nuclei** beamline experiment — both small teams without a dedicated controls engineer, both running a complete, correctly-configured EPICS stack they own and understand.

Declare your project's own identity — name, institution, contact person — and what you need, in one file, `local.yml`. Every installation carries that identity on its Archiver Appliance management page — author, institution, and contact person, right there for anyone who lands on the interface to see whose system it is and who to ask (Olog's own logbook view is the stock Phoebus/Olog UI and isn't branded the same way, though its logbooks and tags are still scoped to your project) — your installation is unmistakably *yours*, not a generic default; this is "proprietary" in the sense of belonging to and being identified with your facility or experiment, not in the sense of commercial or closed-source — RAPIDS itself stays open. In a few hours you have a complete, production-capable EPICS control system: Archiver Appliance, Olog logbook, a working development and IOC-hosting environment, all correctly wired together, all self-tested. The same box doubles as a genuine development workstation, not just a production appliance — a solid foundation to build on, not a black box.

RAPIDS is a fork of the [EPICS Training-VM](https://github.com/epics-training/training-vm) project, and it keeps that heritage deliberately: the same scripted, reproducible, from-source philosophy that makes Training-VM a good *teaching* tool is exactly what makes RAPIDS a trustworthy foundation for a *production* one.

**Tested today on AlmaLinux (RPM-based RHEL derivative).** RAPIDS itself has been developed and validated exclusively on AlmaLinux. Rocky Linux is almost certainly compatible — training-vm, the upstream project RAPIDS is forked from, is itself tested on Rocky — but RAPIDS has not yet been verified there, so treat Rocky as untested rather than unsupported. Porting to Ubuntu/Debian is a separate, genuinely plausible next step, and one we'd actively take on if the community asks for it. If that's you, open an issue and say so.

## What you get

Everything is independently toggled in `local.yml` — enable only what your project needs:

| Component | What it is |
|---|---|
| EPICS Base + support modules | Built from source, the core of any EPICS system |
| Phoebus | The EPICS GUI client, built from source |
| Archiver Appliance | Full three-tier (STS/MTS/LTS) PV data archiving |
| Olog | Electronic logbook, with accounts, logbooks, and tags scoped to your project |
| procServ / manage-procs | Run your own IOCs as supervised, reboot-surviving systemd services |
| NTP sync (chrony) | A shared time reference so PVs from different boxes correlate correctly |
| Firewall rules | Scoped automatically to whatever you actually enabled |
| A project-branded landing page | Links to everything above, labeled with your project's identity |

See [`doc/rapids/architecture.md`](doc/rapids/architecture.md) for how these fit together.

## 5-minute quickstart

Starting from a vanilla AlmaLinux box (RAPIDS's tested target — Rocky Linux is expected to work too, given training-vm's own heritage, but has not yet been verified for RAPIDS itself), logged in as a user named exactly `epics-dev` with sudo rights (create it first if the box doesn't have one yet — this is Training-VM's own convention, and several paths and systemd services further down assume this exact username):

```bash
# 1. Install EPEL (needed by some RAPIDS components)
sudo dnf install -y epel-release

# 2. Let Ansible run privileged tasks without a password prompt
sudo visudo
# add a line like: youruser ALL=(ALL) NOPASSWD: ALL

# 3. Point the installer at RAPIDS instead of the stock Training-VM
cat > ~/bootstrap_setup << 'EOF'
SLUG=main
REPO[vm-setup]=https://github.com/Jack-at-LNL/rapids.git
BRANCH[vm-setup]=rapids
EOF

# 4. Bootstrap: installs git/ansible, clones everything
eval "$(curl -L https://raw.githubusercontent.com/Jack-at-LNL/rapids/rapids/bootstrap.sh)"
cd training

# 5. Replace the generic default local.yml with RAPIDS's own sample, then
#    edit it: project name, institution, contact person, and which
#    components (above) to enable. (The training-collection repo this is
#    based on ships its own generic local.yml at this path - RAPIDS's real
#    settings live in vm-setup/ansible/vars/local.yml.sample instead.)
#
#    Want everything switched on in one go instead of hand-picking
#    components? Copy local.full.stack.istallation.yml (repo root) to
#    local.yml instead - a ready-to-play, full-stack showcase install.
#    See doc/rapids/local-yml-guide.md for a full annotated reference
#    either way.
cp vm-setup/ansible/vars/local.yml.sample local.yml
nano local.yml

# 6. Install (--ask-vault-pass decrypts local.yml's vault-encrypted
#    secrets - e.g. olog_admin_password - into memory for this run only;
#    they are never written back to disk in clear text. Omit the flag
#    only if you didn't vault-encrypt anything in local.yml.)
vm-setup/update.sh --ask-vault-pass
```

That's it — `update.sh` builds, configures, starts, and self-tests everything you enabled. For the full, detailed walkthrough of every `local.yml` setting (vault-encrypted passwords, storage layout, retention policy, accounts, NTP servers, and more), see [`doc/rapids/local-yml-guide.md`](doc/rapids/local-yml-guide.md).

## Documentation

- [`doc/rapids/architecture.md`](doc/rapids/architecture.md) — how the pieces fit together
- [`doc/rapids/local-yml-guide.md`](doc/rapids/local-yml-guide.md) — every `local.yml` setting, explained
- [`doc/rapids/archiver-appliance.md`](doc/rapids/archiver-appliance.md) — Archiver Appliance setup, operation, troubleshooting
- [`doc/rapids/olog-server.md`](doc/rapids/olog-server.md) — Olog accounts, logbooks, troubleshooting
- [`doc/rapids/procserv-manual.md`](doc/rapids/procserv-manual.md) — running your own IOCs under procServ
- [`doc/rapids/ntp-sync-server.md`](doc/rapids/ntp-sync-server.md) — why and how to synchronize time across the project

## License

RAPIDS does not carry a formal license file, matching the upstream [Training-VM](https://github.com/epics-training/training-vm) project it is forked from. Treat it in the same open, collaborative spirit as the wider EPICS community: use it, fork it, adapt it to your project, and please consider sharing improvements back.

## Next steps

Things that are genuinely open, not hidden:

- **Ubuntu/Debian support** — RAPIDS is intensively tested on AlmaLinux today (Rocky Linux is expected to work, given training-vm's own heritage, but hasn't been verified yet for RAPIDS); porting to Debian-family systems is a real possibility on request from the community, not a closed door.
- Questions, issues, and collaboration are welcome — open an issue on this repository.

## AI Assistance Disclosure

Parts of RAPIDS — code, Ansible roles, documentation, and this README — were developed with the assistance of AI tools.
