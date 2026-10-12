# RAPIDS NTP Time Synchronization

## 1. Why this exists, and why it matters

An EPICS control system is rarely one machine. A real automation project typically spans several boxes — possibly several separate RAPIDS installations, possibly PLCs or other automation systems that have nothing to do with RAPIDS at all — each running its own IOCs, each generating PVs with timestamps.

**The Archiver Appliance records each PV sample with the timestamp the IOC itself attached to it, not the time the Archiver received it.** That source timestamp comes directly from the IOC's host operating system clock. If two boxes' clocks disagree, PVs that are physically correlated (a trigger on one box, a readback on another) end up with timestamps that don't actually line up — and no amount of correct Archiver configuration can fix that after the fact, because the wrong timestamp was already recorded at the source.

This is not about achieving laboratory-grade timing precision. It is about every box in the project agreeing on the same clock, closely enough that correlating events across machines in the Archiver's retrieval data, or in Phoebus's Data Browser, actually means something. A common NTP reference — the same one every RAPIDS installation, and ideally every PLC or other automation system in the same project, points at — is the straightforward way to get that.

This is exactly why `system_time` (chrony/NTP sync) is its own independent, explicitly-toggled RAPIDS capability, not something bundled into the Archiver Appliance role: the Archiver only ever reads whatever the OS clock says, and genuinely has no way to request, verify, or report that this clock is actually synchronized. Getting it right is a separate, deliberate step.

## 2. Enabling it on a RAPIDS box

In `local.yml`:

```yaml
system_time: true

ntp_servers:
  - ntp.your-site.example.org   # your project's own reference, if you have one
  - pool.ntp.org                # fallback
```

`ntp_servers` is a list, tried in order; the first entry should be your project's actual time reference if one exists. If every RAPIDS installation, and every other piece of automation equipment in the project, points at the *same* first entry, every clock on the project converges toward the same reference — which is the entire point.

```yaml
system_time_sync_timeout: 120       # seconds to wait for the first sync (default)
system_time_require_sync: false     # default: warn and continue
```

**Set `system_time_require_sync: true` in production.** The default (`false`) is meant for isolated test networks with no NTP reachability at all — it lets the install continue with a clear warning rather than failing outright. In a real deployment, an unsynchronized clock silently corrupts the timestamp correlation this whole mechanism exists to protect; you want the install to stop and tell you, not continue quietly wrong.

## 3. What actually happens

`system_time` installs and enables `chronyd`, deploys `/etc/chrony.conf` from the servers you declared, and then **waits for and verifies a real synchronization**, not just that the service started:
Leap status : Normal
System time : 0.000000091 seconds fast of NTP time
If no server answers within `system_time_sync_timeout`, the install either stops (`system_time_require_sync: true`) or continues with an explicit warning naming every server it tried — never silently.

## 4. Choosing your project's own reference server

If your project doesn't already have one, any of the following work as a sensible single reference point for everything in the project to agree on:

- A dedicated NTP appliance or GPS-disciplined clock already present at the facility (the best choice, if one exists — ask your network/timing group).
- A national metrology institute's public NTP service (e.g. INRIM, `ntp1.inrim.it`/`ntp2.inrim.it`, for installations in Italy) as a stratum-1-adjacent reference.
- The public NTP pool (`pool.ntp.org`), if the site has outbound Internet access and no stricter requirement exists — fine for a training/test deployment, less ideal as the single reference for a real multi-box production project, since you have no control over which pool members answer.

Whatever you choose, **the goal is one shared answer across the whole project** — a RAPIDS box, a second RAPIDS box elsewhere in the same facility, and a PLC-based system all pointing at the same server (or the same short, ordered list of servers) is what actually makes cross-system PV correlation meaningful.

## 5. Verifying it yourself

```bash
systemctl is-active chronyd
chronyc tracking
```

`Leap status: Normal` and a `System time` offset in the microsecond-to-low-millisecond range confirm a healthy sync. `chronyc sources` shows which configured server is actually being used and its reachability.

---

## Appendix: Ansible Automation Architecture

**Role location:** `ansible/roles/system_time/`, invoked from `playbook.yml` early in the play (before `EPICS Base` and every other capability), tagged `[system_time]`, gated by `system_time: true` in `local.yml`.

**Task flow** (`tasks/main.yml`, in order): install `chrony` → render `chrony.conf` from `ntp_servers` → enable/start `chronyd` → check current sync state → restart `chronyd` only if the configuration changed or the clock is not already `Normal` (idempotent — a re-run on an already-synced box does not needlessly restart the daemon) → wait for synchronization (`chronyc waitsync`, bounded by `system_time_sync_timeout`) → report the result → stop or warn depending on `system_time_require_sync`.

**Key variables** (`defaults/main.yml`): `ntp_servers`, `system_time_sync_timeout`, `system_time_require_sync`.

**Template:** `templates/chrony.conf.j2` — one `server <host> iburst` line per entry in `ntp_servers`, plus standard chrony hardening (`makestep 1.0 3`, `rtcsync`).

**Independent of every other role.** No other RAPIDS role reads or waits on `system_time`'s result; the Archiver Appliance, Olog, and any IOC simply read whatever the OS clock reports. This is deliberate: `system_time` is the one place responsible for that clock being right, and it is the only role positioned to actually verify and report on it.
