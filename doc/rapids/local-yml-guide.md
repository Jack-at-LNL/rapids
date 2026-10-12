# RAPIDS `local.yml` Guide

`local.yml` is the single source of truth for a RAPIDS installation — everything the playbook does, it does because `local.yml` says so. This guide goes through every setting in `ansible/vars/local.yml.sample`, in the order it appears, with the reasoning behind each one.

If you just want the fastest path to a working install, see the README's 5-minute quickstart instead; come back here when you want to understand *why* a setting exists, or when you're configuring something beyond the defaults.

## 1. Where this file lives, and how it gets there

`bootstrap.sh` copies `ansible/vars/local.yml.sample` to a real `local.yml` the first time you run it, and symlinks it into place at `vm-setup/ansible/vars/local.yml`. `update.sh` always reads it explicitly (`ansible-playbook playbook.yml -e "@vars/local.yml"`) — this is the one file that matters; nothing else is auto-loaded.

You can also keep multiple named configurations side by side (e.g. for testing a second project on the same machine) and select one explicitly:

```bash
ansible-playbook ... playbook.yml -e @vars/myVM.yml
```

## 2. Modules to build

```yaml
m_base: true
m_asyn: true
m_stream: true
```

Each `m_*` variable builds one EPICS module from source. `m_base` is effectively mandatory — almost everything else depends on it. Add more as your project needs them (e.g. `m_p4p`, `m_pvaPy`, `m_seq`, `m_areadetector`, `m_opcua` — see the sample file's comments for the full list this fork knows about). Only enable what you actually need; each one adds real build time.

## 3. Services

```yaml
# phoebus: true
# archiver_appliance: true
# docker: true
# bluesky: true
```

The larger, optional capabilities inherited from Training-VM. `phoebus: true` is required before `olog_server` (Olog's build needs Maven, which the `phoebus` role installs) and before either Phoebus-client-config role can do anything.

## 4. RAPIDS roles

```yaml
# system_time: true             # NTP synchronisation with chrony
# olog_server: true             # Olog electronic logbook server (needs phoebus: true for Maven)
# olog_client_config: true      # Phoebus: Olog logbook (Ctrl+L)   - needs phoebus: true
# archiver_client_config: true  # Phoebus: Archiver data (Ctrl+D)  - needs phoebus: true
```

The capabilities this fork adds on top of Training-VM. Each is documented in its own manual:

- `system_time` — [`ntp-sync-server.md`](ntp-sync-server.md). Turn this on for any real deployment; a shared time reference is what makes cross-box PV correlation meaningful at all.
- `olog_server` — [`olog-server.md`](olog-server.md).
- `olog_client_config` / `archiver_client_config` — wire Phoebus's logbook (Ctrl+L) and data browser (Ctrl+D) to the Olog/Archiver this same install just set up. There is no reason to enable `olog_server` without also enabling `olog_client_config`, unless Phoebus itself is disabled.
- `rapids_procserv` (see section 7 below) — [`procserv-manual.md`](procserv-manual.md).
- `archiver_appliance` itself lives under "Services" above (section 3), inherited from Training-VM's own naming, not the "RAPIDS roles" block — a naming quirk worth knowing about, not a bug.

## 5. Project branding

```yaml
# rapids_project_name: "My Project"
# rapids_author_name: "Your Name"
# rapids_author_email: "your.email@example.org"
# rapids_institution: "Your Institution"
```

This is what makes an installation genuinely *yours* rather than a generic default — it appears on the landing page, in the Olog's first auto-created logbook, and in the generated documentation footers. Fill these in for every real deployment.

**Avoid `-` and `:` in `rapids_project_name` and `rapids_instance_name` (below).** The Archiver Appliance's `ConvertPVNameToKey` converts both characters into directory separators on disk — `"ANTHEM-SPES"` is stored as a literal nested folder `ANTHEM/SPES`, not as one name. Harmless, but confusing to browse later. Use a space, an underscore, or just run the words together instead.

## 6. Instance name

```yaml
# rapids_instance_name: "vm01"
```

Used in the Archiver healthcheck's and the procServ self-check's test PV names. **Set this explicitly whenever more than one RAPIDS installation might run on the same network.** Without it, two installs of the same project could serve PVs with identical names (e.g. two `"My Project:healthcheck:counter"`), and EPICS clients could connect to either one unpredictably — a real, silent correctness problem, not a cosmetic one. Give each VM or installation its own value: the hostname, or a short site/unit label — never the project name itself, which is already covered by `rapids_project_name`.

This same convention is worth following for any production IOC you create yourself with `manage-procs` (see the next section) — scope your own PV names the same way, for the same reason.

## 7. procServ

```yaml
# rapids_procserv: true
# rapids_procserv_selfcheck: true
```

Installs procServ and `manage-procs` — the EPICS community's own systemd integration — so you can run your own production IOCs as properly supervised, reboot-surviving services. **RAPIDS does not create or manage any production IOC itself.** It installs the tool, proves the installation genuinely works with a one-time, self-disabling check (`rapids_procserv_selfcheck`, on by default), and then steps back entirely — you create and manage your own IOCs by hand, exactly as on any EPICS workstation. See [`procserv-manual.md`](procserv-manual.md) for the full walkthrough, including a real production-IOC example.

## 8. Olog logbooks and tags

```yaml
# olog_initial_logbooks:
#   - { name: "{{ rapids_project_name }}", owner: "olog-logs", state: "Active" }
#   - { name: "operations",    owner: "olog-logs", state: "Active" }
#   - { name: "commissioning", owner: "olog-logs", state: "Active" }
#   - { name: "maintenance",   owner: "olog-logs", state: "Active" }
#   - { name: "faults",        owner: "olog-logs", state: "Active" }
# olog_initial_tags:
#   - { name: "follow-up" }
#   - { name: "resolved" }
#   - { name: "reference" }
```

Seeded once, at install time (requires `olog_server: true`). The first logbook is named after the project itself (`rapids_project_name`) automatically, so every entry has a home from day one; the rest reflect how a control room actually files entries day to day. Edit this list freely to match how your team actually works — adding more later, after install, doesn't require editing `local.yml` at all (see [`olog-server.md`](olog-server.md) section 3 for the standalone `manage-logbooks.sh`/`manage-tags.sh` scripts).

## 9. Time servers

```yaml
# ntp_servers:
#   - ntp.example.org
#   - pool.ntp.org
```

First entry is primary, the rest are fallbacks, tried in order. See [`ntp-sync-server.md`](ntp-sync-server.md) for the full reasoning — in short, every box in the same project should point at the same first entry, so every clock on the project converges toward the same reference.

## 10. Service endpoints

```yaml
# olog_server_url: "http://olog.example.org:8080/Olog"
# archappl_host: archiver.example.org
```

Default to this machine (`localhost`/its own address). Override these only when Phoebus on this box needs to reach an Olog or Archiver running somewhere else — a single-box install doesn't need either.

## 11. Olog passwords — the vault workflow

```yaml
# olog_admin_password: !vault |
#   ...
```

**Required when `olog_server` is true.** Never written in clear text. The workflow:

```bash
ansible-vault encrypt_string 'YourSecurePassword' --name 'olog_admin_password' >> local.yml
```

This appends an encrypted `!vault` block directly to `local.yml`. Run `vm-setup/update.sh --ask-vault-pass` afterward — Ansible asks for the vault password once per run and decrypts in memory only.

**Before appending a second `ansible-vault encrypt_string` block, confirm the file ends in a newline** (`printf '\n' >> local.yml` first). Two appends with no newline between them silently glue into invalid YAML that only fails much later, often confusingly. Validate after any manual edit:

```bash
python3 -c "
import yaml
class L(yaml.SafeLoader): pass
L.add_constructor('!vault', lambda l, n: n.value)
d = yaml.load(open('local.yml'), Loader=L)
print(len(d), 'keys \u2014 valid')
"
```

## 12. Personal Olog accounts

```yaml
# olog_users:
#   - { name: user1, password: "{{ olog_user1_password }}", admin: true }
#   - { name: user2, password: "{{ olog_user2_password }}" }
#   - { name: user3, password: "{{ olog_user3_password }}" }
```

One vault-encrypted value per user, same mechanism as the admin password:

```bash
ansible-vault encrypt_string 'Password1' --name 'olog_user1_password' >> local.yml
```

Accounts with `admin: true` get full management rights (logbooks, tags, properties); every account, admin or not, can write log entries. See [`olog-server.md`](olog-server.md) section 2 for recovering a forgotten password and for adding or changing an account after the initial install.

## 13. Firewall

```yaml
# rapids_firewall_extra_ports: ['5065/udp']
```

Channel Access, PV Access, Olog, and the Archiver Appliance's ports are opened automatically based on what you enabled elsewhere in this file — you only need this if your site needs something beyond that default set.

---

## A complete example

A single-box installation for a small beamline project, with Olog, the Archiver, procServ for production IOCs, and NTP sync against a site reference:

```yaml
m_base: true
m_asyn: true
m_stream: true

phoebus: true
archiver_appliance: true

system_time: true
olog_server: true
olog_client_config: true
archiver_client_config: true

rapids_project_name: "ANTHEM"
rapids_author_name: "Your Name"
rapids_author_email: "your.email@example.org"
rapids_institution: "INFN Laboratori Nazionali di Legnaro"
rapids_instance_name: "vm01"

rapids_procserv: true

ntp_servers:
  - ntp1.inrim.it
  - pool.ntp.org
system_time_require_sync: true

olog_admin_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
```

Then:

```bash
vm-setup/update.sh --ask-vault-pass
```
