# RAPIDS Architecture

A one-page picture of how RAPIDS fits together — for the per-component details, see the manuals in this folder.

## The idea in one sentence

RAPIDS turns a vanilla Linux box into a working, production-capable EPICS control system by running a single Ansible playbook, driven entirely by one file you edit: `local.yml`.

## The layers

```text
local.yml <- the one file you edit: what to install, your project's
             identity, your credentials (vault-encrypted)
  |
  v
ansible/playbook.yml <- reads local.yml, decides which roles to run
  |
  v
Ansible roles <- one role per capability, each independently toggled
  |
  +-- system_time <- NTP sync (chrony), runs first - see ntp-sync-server.md
  +-- m_base, m_asyn, ... <- EPICS Base and support modules, built from source
  +-- phoebus <- the EPICS GUI client, built from source
  +-- archiver_appliance <- EPICS Archiver Appliance + Tomcat + MariaDB
  +-- olog_server <- Olog electronic logbook + ElasticSearch + MongoDB
  +-- rapids_procserv <- procServ + manage-procs, for running your own IOCs
  +-- rapids_security <- firewall rules scoped to what's actually enabled
  +-- rapids_landing_page <- a project-branded homepage linking everything up
  +-- phoebus_client_config <- wires Phoebus to Olog/Archiver automatically
  |
  v
A running control system <- services active, firewalled, self-tested
```

## Three ideas that shape everything else

**Declarative, not imperative.** `local.yml` describes the state you want; running `update.sh` brings the machine to that state, whether it's a first install or the hundredth re-run. Nothing is hand-run once and forgotten — if it matters, it's in `local.yml` and Ansible owns it.

**Self-verifying, not just self-installing.** Every major capability (Archiver, Olog, procServ) installs its own healthcheck script alongside itself, and that script runs automatically at the end of installation — not a separate manual step, not something you have to remember. A failure is reported loudly in the install output but does not halt the rest of the install, so one broken piece never blocks everything else from coming up. The same script stays on the machine afterward for a field engineer to re-run by hand, any time, with no network or source-tree access required.

**Correct, not just convenient, by default.** `system_time` runs before anything else precisely because PV timestamps are attached at the source IOC's own OS clock — if that clock is wrong, no later configuration can fix the data. The same philosophy shows up elsewhere: the Archiver's LTS tier has no automatic deletion (data is never silently discarded), and `rapids_instance_name` exists specifically so that two RAPIDS installations on the same network never collide on PV names. RAPIDS prefers to fail loudly or ask for an explicit choice over quietly doing something that could be wrong.

## What RAPIDS deliberately does *not* do

It does not manage your production IOCs' lifecycle — `rapids_procserv` installs the tool (procServ + `manage-procs`) and proves it works, then steps back entirely; you create and manage your own IOCs by hand, exactly as on any EPICS workstation. It does not back up Olog or the Archiver Appliance's data today — that gap is tracked, not hidden (see each manual's own notes). It is tested, today, on AlmaLinux (RPM-based RHEL derivative) only — Rocky Linux is expected to work, given training-vm's own heritage, but has not yet been verified for RAPIDS itself.

## Where to go next

- **New to RAPIDS?** Start with the main [`README.md`](../../README.md) for a 5-minute quickstart.
- **Configuring your install?** [`local-yml-guide.md`](local-yml-guide.md) covers every setting in depth.
- **Operating a specific service?** [`archiver-appliance.md`](archiver-appliance.md), [`olog-server.md`](olog-server.md), [`procserv-manual.md`](procserv-manual.md), [`ntp-sync-server.md`](ntp-sync-server.md).
