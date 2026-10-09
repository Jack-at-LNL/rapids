# RAPIDS EPICS Archiver Appliance — Setup, Configuration and Verification

## 1. Overview

Enabling `archiver_appliance: true` in `local.yml` installs the EPICS Archiver Appliance 2.0.7 on Tomcat 9.0.79, with MariaDB as its configuration database:

| Component | Version | Role |
|---|---|---|
| Archiver Appliance | 2.0.7 | Engine, management, retrieval and ETL web apps |
| Tomcat | 9.0.79 | Hosts the four Archiver web applications |
| MariaDB | 10.5.29 | Stores `PVTypeInfo` and appliance configuration |

The archiver automatically moves data through three tiers: **STS** (Short-Term Storage, hourly files, fast access) → **MTS** (Medium-Term Storage, daily files) → **LTS** (Long-Term Storage, permanent).

## 2. Storage Location

Each storage tier is independently configurable in `local.yml`:

```yaml
archiver_appliance_storage: "/var/lib/archiver-appliance"          # parent, FHS convention
archiver_appliance_storage_sts: "{{ archiver_appliance_storage }}/sts"
archiver_appliance_storage_mts: "{{ archiver_appliance_storage }}/mts"
archiver_appliance_storage_lts: "{{ archiver_appliance_storage }}/lts"
```

Override any tier independently — for example, keep STS on fast local disk while pointing LTS at a large NFS mount:

```yaml
archiver_appliance_storage_lts: "/mnt/archive-nfs/lts"
```

This matches the EPICS Archiver Appliance community's own documented pattern (`ARCHAPPL_STORAGE_TOP` and independent per-tier paths), not a RAPIDS invention.

**Set this before archiving any real PVs.** Each PV's storage location is persisted into MariaDB's `PVTypeInfo` the moment it starts being archived. Changing `archiver_appliance_storage_*` afterward does **not** migrate existing data — the archiver keeps writing wherever it was originally told, and old data becomes effectively orphaned. Decide your storage layout at install time.

## 3. Retention Policy

```yaml
archiver_appliance_mts_hold_days: 7                         # days in MTS before moving to LTS
archiver_appliance_lts_partition_granularity: "PARTITION_MONTH"   # LTS never rotates — this is permanent archive
```

These are the only two retention values rendered into `policies.py` (`templates/rapids-policies.py.j2`); everything else — the four named policies (`Default`, `BPMS`, `2HzPVs`, `3DaysMTSOnly`), per-record-type field archiving — is fixed logic inherited from the upstream policy file, with RAPIDS's own historical fixes preserved in the file's own comments. LTS has no `hold=` parameter by design: once data reaches LTS, it is never automatically deleted or rotated.

To add a genuinely new policy or change the field-archiving logic, edit `ansible/roles/archiver_appliance/templates/rapids-policies.py.j2` directly — this is the single, canonical source; there is no second mechanism to keep in sync.

## 4. Health Check — Automatic and On-Demand

A verification script runs **automatically, once, at the very end of installation** — after every other role (firewall, homepage, Olog, Phoebus client config) has finished, so its own checks (archiving, firewall-dependent PV access) aren't run against a half-configured system. Its result appears directly in the install output:

```
SUMMARY: PASS=14 FAIL=0 WARN=2   report: /home/epics-dev/archiver-tests-<date>.txt
```

It stays installed afterward for manual re-runs:

```bash
bash -l /opt/epics-tools/archiver/scripts/rapids_archiver_healthcheck.sh
bash -l /opt/epics-tools/archiver/scripts/rapids_archiver_healthcheck.sh --no-restart   # skip the restart test
bash -l /opt/epics-tools/archiver/scripts/rapids_archiver_healthcheck.sh --stop-ioc     # stop the test IOC it starts
```

It checks, in order: service/port status, the management page, end-to-end archiving of two test PVs (`{{ rapids_project_name }}:{{ rapids_instance_name }}:healthcheck:counter` over PV Access, `...:healthcheck:noise` over Channel Access — see `local.yml.sample` for `rapids_instance_name`, which keeps two RAPIDS installs on the same network from colliding on these names), short-term storage growth, and exposure/credential warnings — a complete report is written to `~/archiver-tests-<timestamp>.txt`.

## 5. CLI Reference

```bash
# Service status
systemctl status archiver-appliance mariadb
ss -tlnp | grep -E ":17665|:3306"

# Appliance identity and version
curl -s "http://localhost:17665/mgmt/bpl/getApplianceInfo?id=appliance0" | python3 -m json.tool
curl -s "http://localhost:17665/mgmt/bpl/getVersions" | python3 -m json.tool

# Archive a PV
curl -s "http://localhost:17665/mgmt/bpl/archivePV?pv=<pv_name>"
curl -s "http://localhost:17665/mgmt/bpl/archivePV?pv=ca://<pv_name>"   # force Channel Access

# Check a PV's status
curl -s "http://localhost:17665/mgmt/bpl/getPVStatus?pv=<pv_name>" | python3 -m json.tool

# List all archived PVs
curl -s "http://localhost:17665/mgmt/bpl/getAllPVs" | python3 -m json.tool

# Retrieve data
curl -s "http://localhost:17665/retrieval/data/getData.json?pv=<pv_name>&from=<ISO8601>&to=<ISO8601>"

# Storage inspection
sudo find /var/lib/archiver-appliance -name "*.pb" -mtime -1
sudo du -sh /var/lib/archiver-appliance/{sts,mts,lts}
```

## 6. Known, Accepted Limitations

These are deliberate trade-offs for the training/development use case, not oversights — flagged clearly by the health check's own `WARN` lines on every run:

- **MariaDB uses the default `archappl`/`archappl` credentials.** This is a stated, intentional default for this deployment. If your site requires changing it, the password is hardcoded in **four** places that must all be updated together, or the Archiver Appliance will fail to start (confirmed directly: a mismatch here reproduces the exact "Cannot create JDBC driver" / stuck-startup failure documented in the Appendix's `context.xml` note) - `tasks/install_mariadb.yml` (the MariaDB user itself), `tasks/main.yml` (the schema-install command and the `PVTypeInfo` nullability fix, two occurrences), and `templates/context.xml.j2` (the JDBC `Resource` Tomcat uses to connect). There is no single variable for this yet - each location is a literal string today.
- **The management interface (`:17665`) accepts requests with no authentication.** Limit network access to your control network; do not expose this port beyond it.

## 7. Phoebus Client Integration

Configured automatically when `archiver_client_config: true`, written into `/opt/epics-tools/config/preferences.ini`:

```ini
org.csstudio.trends.databrowser3/urls=pbraw://<host>:17665/retrieval
org.csstudio.trends.databrowser3/archives=pbraw://<host>:17665/retrieval
org.csstudio.trends.databrowser3/use_default_archives=true
```

Launch Phoebus with `/usr/local/bin/run-phoebus` to pick this up.

---

## Appendix: Ansible Automation Architecture

**Role location:** `ansible/roles/archiver_appliance/`, tagged `[archiver_appliance]`, gated by `archiver_appliance: true` in `local.yml`.

**Task flow** (`tasks/main.yml`, in order): MariaDB install → Tomcat install (`server.xml` static copy, `context.xml` **templated** — see note below) → Archiver Appliance download/unpack → storage directory creation (per-tier) → `appliances.xml` → `policies.py` (templated) → `archappl.properties` → `setenv.sh` (exports `ARCHAPPL_*_FOLDER` from the per-tier variables) → database table setup → systemd service → homepage link → healthcheck script installation.

**Key variables** (`defaults/main.yml`): `archiver_appliance_storage`, `archiver_appliance_storage_sts/mts/lts`, `archiver_appliance_mts_hold_days`, `archiver_appliance_lts_partition_granularity`, `archiver_appliance_healthcheck_dir`.

**Templates:** `templates/rapids-policies.py.j2` (retention policy, single source of truth — see Section 3), `templates/setenv.sh.j2`, `templates/appliances.xml.j2`, `templates/archappl.properties.j2`, `templates/context.xml.j2` (Tomcat's own `conf/context.xml` — see note below), `templates/rapids_archiver_healthcheck.sh.j2` (rendered with `rapids_project_name`/`rapids_instance_name` for the PV names used in Section 4's end-to-end test).

**`context.xml` — mandatory JDBC resource, a confirmed, hard-won fix.** `context.xml.j2` defines a Tomcat JNDI `jdbc/archappl` DataSource that the Archiver Appliance's persistence layer looks up *unconditionally* at startup — it is not optional, despite the surrounding `mysql_connection_pool` variable name suggesting a choice (`defaults/main.yml` sets it `true` for exactly this reason). Without it, Tomcat starts but the appliance never leaves its startup retry loop, `PVTypeInfo` stays empty, and the management interface returns HTTP 503/500 indefinitely - confirmed directly on a from-zero install, where this path had never previously been exercised (every earlier test in this project's history reused an already-provisioned Tomcat, where `install_tomcat.yml`'s `context.xml` task is skipped entirely once Tomcat exists). The JDBC URL in this file uses `localhost`, matching every other MariaDB connection in this role - if you ever see it referencing anything else, that is this exact bug returning.

**The healthcheck run itself lives outside this role**, in `ansible/tasks/run_archiver_healthcheck.yml`, imported as the last task in `playbook.yml` — after every role has finished — for the same reason the Training-VM homepage reassembly handler is defined at the play level rather than inside any one role: it must run regardless of which other roles were enabled, and only once everything it depends on (firewall ports, homepage footer) is genuinely in place.

**Follow-up work, not yet implemented** (tracked, not forgotten): ElasticSearch-aware backup for Olog and the Archiver Appliance - neither currently has a backup mechanism (see `doc/rapids/olog-server.md`, section 6, for the reasoning). For running your own production IOCs under procServ/systemd, see `doc/rapids/procserv-manual.md` - the transient test IOC this healthcheck starts is diagnostic only, not a template for production use.
