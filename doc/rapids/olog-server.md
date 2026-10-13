# RAPIDS Olog Server — Setup, Configuration, Accounts and Backup

## 1. Overview

Enabling `olog_server: true` in `local.yml` installs a complete Olog electronic logbook stack:

| Component | Version | Role |
|---|---|---|
| Olog Service | 5.1.2 | REST API, built from [phoebus-olog](https://github.com/Olog/phoebus-olog) source |
| ElasticSearch | 8.11.0 | Stores and indexes log entry content **and logbook/tag definitions** |
| MongoDB | 4.4 or 7.0 (auto-selected by CPU) | Stores log entry metadata and attachments |

Authentication uses an **embedded, in-memory LDAP server** — not MongoDB, not an external directory. It re-imports its account list fresh on every Olog startup.

## 2. Accounts

### Setting passwords

```bash
# Required — admin account
ansible-vault encrypt_string 'YourSecurePassword' --name 'olog_admin_password' >> local.yml

# Optional — one per personal account
ansible-vault encrypt_string 'AnotherPassword' --name 'olog_user1_password' >> local.yml
```

Then in `local.yml`:
```yaml
olog_users:
  - { name: user1, password: "{{ olog_user1_password }}", admin: true }
  - { name: user2, password: "{{ olog_user2_password }}" }
```

**Before appending a second `ansible-vault encrypt_string` command, confirm the file ends in a newline** (`printf '\n' >> local.yml` first). Two appends with no newline between them silently glue into invalid YAML that only fails much later. Validate after any manual edit:
```bash
python3 -c "
import yaml
class L(yaml.SafeLoader): pass
L.add_constructor('!vault', lambda l, n: n.value)
d = yaml.load(open('local.yml'), Loader=L)
print(len(d), 'keys — valid')
"
```

Accounts with `admin: true` (plus `olog_admin_user` always) get full management rights (logbooks, tags, properties). Every account, admin or not, can write log entries.

### Recovering a forgotten password

- **Deployed system** (no vault password needed):
  ```bash
  sudo grep -A6 "uid=user1,ou=People" /opt/epics-tools/olog/config/rapids-users.ldif \
    | grep userPassword | awk '{print $2}' | base64 -d; echo
  ```
- **Before deployment**: extract just the `$ANSIBLE_VAULT;1.1;AES256` block from `local.yml` into a file, then `ansible-vault decrypt tempfile --output=-`.

### Adding or changing accounts without reinstalling

Unlike logbooks and tags (section 3), there is no lightweight standalone
script for accounts - the embedded-LDAP user file is rendered and the
service restarted only as part of the full Olog install task
(`install_olog.yml`, tag `olog`). To add a user or change a password:

1. Edit `olog_users` in `local.yml` (add/change an entry), or update
   `olog_admin_password` - encrypted with `ansible-vault encrypt_string`,
   same as the initial setup above.
2. Re-run:
```bash
   ./vm-setup/update.sh --ask-vault-pass --tags olog_server
```

This re-runs the whole Olog role, including a full rebuild from source
(5-10 minutes) and a cleanup pass that removes and recreates
`olog_install_dir`/`olog_data_dir`/`olog_log_dir` first - this is safe:
log entries, logbooks, tags, and attachments all live in MongoDB and
ElasticSearch, neither of which this cleanup touches, so nothing you
have already logged is at risk. The rebuild itself is simply the cost of
there being no finer-grained path today.

## 3. Logbooks and Tags

Declared in `local.yml`, not the role's own defaults (which are empty):

```yaml
olog_initial_logbooks:
  - { name: "{{ rapids_project_name }}", owner: "olog-logs", state: "Active" }
  - { name: "operations",    owner: "olog-logs", state: "Active" }
  - { name: "commissioning", owner: "olog-logs", state: "Active" }
  - { name: "maintenance",   owner: "olog-logs", state: "Active" }
  - { name: "faults",        owner: "olog-logs", state: "Active" }

olog_initial_tags:
  - { name: "follow-up" }
  - { name: "resolved" }
  - { name: "reference" }
```

The first logbook is named after your project automatically. Olog also ships its own built-ins (`controls`, `operations`, `alarm`) regardless of what you declare.

### Adding more without reinstalling

```bash
/opt/epics-tools/olog/scripts/manage-logbooks.sh add "NEW_NAME" [owner]
/opt/epics-tools/olog/scripts/manage-logbooks.sh delete "NAME"
/opt/epics-tools/olog/scripts/manage-logbooks.sh list

/opt/epics-tools/olog/scripts/manage-tags.sh add "new-tag"
/opt/epics-tools/olog/scripts/manage-tags.sh delete "tag-name"
/opt/epics-tools/olog/scripts/manage-tags.sh list
```

## 4. REST API — the one gotcha that matters most

**Creating a log entry is `PUT`, not `POST`.** `POST /Olog/logs` returns 405 and looks like an auth failure — it isn't.

```bash
curl -X PUT http://localhost:8080/Olog/logs \
  -u admin:YourPassword -H "Content-Type: application/json" \
  -d '{"title":"Example","description":"...","logbooks":[{"name":"operations"}],"level":"Info"}'
```

## 5. Health Check and Troubleshooting

### 5.0 Automatic healthcheck — start here

A verification script (`rapids_olog_healthcheck.sh`) runs **automatically, once, at the end of installation** - services, authentication (including that Olog's built-in demo accounts are correctly refused), logbook/tag/entry/attachment round-trips through the real REST API, an optional restart-persistence check, and confirmation that no backup mechanism is unexpectedly present. Its result appears directly in the install output:

```
SUMMARY: PASS=26 FAIL=0 WARN=1   report: /home/epics-dev/rapids-selfchecks/olog-tests-<date>.txt   ids: /home/epics-dev/rapids-selfchecks/olog-test-ids.txt
```

The expected `WARN=1` is almost always the note about port 8389 - see section 5.2.

It stays installed afterward for manual re-runs:

```bash
OLOG_PASSWORD='YourPassword' bash /opt/epics-tools/olog/scripts/rapids_olog_healthcheck.sh
OLOG_PASSWORD='YourPassword' bash /opt/epics-tools/olog/scripts/rapids_olog_healthcheck.sh --no-restart   # skip the restart test
bash /opt/epics-tools/olog/scripts/rapids_olog_healthcheck.sh   # omit OLOG_PASSWORD to be prompted interactively instead
```

If it reports a failure, the sections below (5.1 onward) are how to dig into *why* - work through them in order, each narrows down where a problem actually is.

### 5.1 Are the underlying services even running?

```bash
for s in olog elasticsearch mongod; do
  echo -n "$s: "; systemctl is-active $s
done
```
All three must say `active`. If one doesn't:
```bash
sudo journalctl -u <service> -n 50 --no-pager
```

### 5.2 Are the ports actually listening?

```bash
ss -tlnp | grep -E ":8080|:9200|:27017|:8389"
```
Expect `8080` (Olog, all interfaces), `9200` (ElasticSearch, loopback only), `27017` (MongoDB, loopback only). If Olog's port is missing, check `journalctl -u olog`; a missing 9200 or 27017 means the Olog service will start but every API call will fail or hang.

**Port 8389** is Olog's Spring Boot Actuator management endpoint, bound to all interfaces but not opened in the firewall (only `8080/tcp` is) - not reachable from outside this host despite the `0.0.0.0` bind.

### 5.3 Is Olog itself healthy, and can it see its dependencies?

```bash
curl -s http://localhost:8080/Olog | python3 -m json.tool
```
A healthy response looks like:
```json
{
  "name": "Olog Service",
  "version": "5.1.2",
  "elastic": {"status": "Connected", "clusterName": "olog-cluster", "..."},
  "mongoDB": "{type=STANDALONE, ..., state=CONNECTED}"
}
```
`"status": "Connected"` and `state=CONNECTED` are the two things to actually read — not just that the request succeeded. **Logbooks and tags live in ElasticSearch, not MongoDB** — if ElasticSearch is down, `GET /Olog/logbooks` fails outright with a 500 even though Olog's own process is running fine:
```bash
curl -s http://localhost:8080/Olog/logbooks
# {"timestamp":...,"status":500,"error":"Internal Server Error","message":"Failed to find logbooks",...}
```
That specific error message means: go check ElasticSearch, not Olog.

### 5.4 Check ElasticSearch and MongoDB directly

```bash
curl -s http://localhost:9200/_cluster/health | python3 -m json.tool
# "status" should be "green" or "yellow" — "red" means real trouble

mongosh --quiet --eval "db.runCommand({ping: 1})" olog
# or on older installs: mongo --quiet --eval "db.runCommand({ping: 1})" olog
# expect: { ok: 1 }
```

### 5.5 Can accounts actually log in and write?

```bash
for u in admin user1 user2 user3; do
  pw=$(sudo grep -A6 "uid=${u},ou=People" /opt/epics-tools/olog/config/rapids-users.ldif \
    | grep userPassword | awk '{print $2}' | base64 -d)
  l=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/Olog/login \
    -H "Content-Type: application/json" -d "{\"username\":\"${u}\",\"password\":\"${pw}\"}")
  echo "${u}: login ${l}"
done
```
`200` for every configured account. A wrong password returns `401`. If an account you expect to exist doesn't work, check the rendered LDIF directly:
```bash
sudo cat /opt/epics-tools/olog/config/rapids-users.ldif
```

### 5.6 What logbooks, tags, and entries actually exist right now?

```bash
# Logbooks
curl -s http://localhost:8080/Olog/logbooks | python3 -m json.tool

# Tags
curl -s http://localhost:8080/Olog/tags | python3 -m json.tool

# Recent entries — id, owner, title, most useful for "did my submission actually land"
curl -s "http://localhost:8080/Olog/logs/search?size=20" | python3 -c '
import sys, json
for l in json.load(sys.stdin)["logs"]: print(l["id"], l["owner"], "-", l["title"])'

# A specific logbook or tag only
curl -s "http://localhost:8080/Olog/logs/search?logbooks=operations&size=10" | python3 -c '
import sys, json
for l in json.load(sys.stdin)["logs"]: print(l["id"], l["owner"], "-", l["title"])'
```

### 5.7 Phoebus can't see my logbooks / entries don't appear

```bash
# Confirm this is the file run-phoebus actually reads
sudo grep -n "BEGIN OLOG\|logbook_factory\|olog_url" /opt/epics-tools/config/preferences.ini
```
- **`logbook_factory` missing, or shows `inmemory`**: Phoebus isn't talking to Olog at all — every entry is discarded silently. It must read `org.phoebus.logbook/logbook_factory=olog-es`.
- **A stray older block appears before the correct one**: comment-line duplication from a previous version; only one `# BEGIN OLOG CONFIGURATION` block should exist.
- **Always launch with `/usr/local/bin/run-phoebus`**, never a hand-typed `-settings` path — it points at the wrong file otherwise.

If the dialog itself stays open with no error message after clicking Submit: **that's a wrong password, not a connection problem.** Phoebus 5.0.2 fails silently in this case. Compare the length of what you typed against the real password (Section 2, Recovering a forgotten password).

### 5.8 One-shot summary check

Useful as a quick "is everything actually fine" command:
```bash
echo "--- services ---"
for s in olog elasticsearch mongod; do echo -n "$s: "; systemctl is-active $s; done
echo "--- Olog info ---"
curl -s http://localhost:8080/Olog | python3 -m json.tool
echo "--- counts ---"
curl -s http://localhost:8080/Olog/logbooks | python3 -c 'import sys,json; print(len(json.load(sys.stdin)), "logbooks")'
curl -s http://localhost:8080/Olog/tags | python3 -c 'import sys,json; print(len(json.load(sys.stdin)), "tags")'
curl -s "http://localhost:8080/Olog/logs/search?size=1000" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["logs"]), "entries")'
```

## 6. Phoebus Client Integration

File: `/opt/epics-tools/config/preferences.ini`. Launcher: `/usr/local/bin/run-phoebus`.

```ini
org.phoebus.logbook/logbook_factory=olog-es
org.phoebus.olog.es.api/olog_url=http://<host>:8080/Olog
org.phoebus.olog.es.api/levels=Info,Warning,Problem,Request,Suggestion
org.phoebus.logbook.olog.ui/default_logbooks=operations
org.phoebus.logbook.olog.ui/default_logbook_query=desc=*&start=1 week&end=now
org.phoebus.ui/save_credentials=true
```

---

## Appendix: Ansible Automation Architecture

For anyone who needs to modify how this is installed, not just operate it day-to-day.

**Role location:** `ansible/roles/olog_server/`, invoked from `playbook.yml` under tags `[olog_server, olog]`, gated by `olog_server: true` in `local.yml`.

**Task flow** (`tasks/main.yml`, in order):
1. Password/precondition asserts (refuses unset or demo passwords)
2. `install_mongodb.yml` — version chosen by `/proc/cpuinfo` AVX detection (4.4 no-AVX, 7.0 with)
3. `install_elasticsearch.yml`
4. `install_olog.yml` — clones and builds `phoebus-olog` with Maven, renders `rapids-users.ldif.j2` and `application.properties`
5. Login/auth verification against the running service
6. `seed_initial_data.yml` — creates `olog_initial_logbooks`/`olog_initial_tags` via the REST API
7. `setup_backup.yml` — installs `manage-logbooks.sh`/`manage-tags.sh` and `rapids_olog_healthcheck.sh`, then runs it non-interactively (`OLOG_PASSWORD` via environment - Section 5.0)

**Key variables** (`defaults/main.yml`, overridden in `local.yml`): `olog_admin_user`, `olog_admin_password`, `olog_users`, `olog_initial_logbooks`, `olog_initial_tags`, `olog_install_dir`, `olog_port`.

**Templates:** `templates/rapids-users.ldif.j2` (accounts/groups), `templates/scripts/manage-*.sh.j2`. `files/scripts/rapids_olog_healthcheck.sh` is a plain copy, not templated - it reads its scope (project/instance context, password) entirely from the environment at runtime, same pattern as the Archiver and procServ healthcheck scripts.

**Companion role:** `phoebus_client_config` writes the Phoebus-side block into `/opt/epics-tools/config/preferences.ini` (Section 6); its file path is set by `phoebus_settings_file` in its own defaults, matching what `/usr/local/bin/run-phoebus` (installed by the `phoebus` role) actually launches with.
