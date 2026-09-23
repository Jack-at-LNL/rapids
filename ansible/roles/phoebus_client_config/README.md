# RAPIDS - Olog Client Configuration Role

## Description

Ansible role for configuring Phoebus client to connect to Olog electronic logbook server. This role rebuilds Phoebus with the olog-es factory and configures default search parameters.

**Institution:** INFN Laboratori Nazionali di Legnaro  
**Author:** Mauro Giacchini  
**Project:** RAPIDS

## Features

- **Automatic Factory Configuration**: Sets Phoebus to use olog-es logbook factory
- **Phoebus Rebuild**: Recompiles core-logbook and phoebus-product with new factory
- **Default Query Setup**: Configures default logbook and time range (last 24 hours)
- **Clean Configuration**: Removes duplicate/old Olog settings before applying new ones
- **Dynamic Data**: Can fetch logbooks and tags from Olog server via REST API

## Requirements

- **Phoebus**: Installed via epics-tools role
- **Olog Server**: Running and accessible
- **Maven**: 3.6+ (provided by epics-tools role)
- **Java**: OpenJDK 17+ (provided by epics-tools role)

## Dependencies

- `epics-tools` role (provides Phoebus, Maven, Java)
- `olog_server` role (provides Olog REST API)

## Role Variables

### Server Connection
```yaml
olog_server_url: "http://olog.example.com:8080/Olog"
olog_username: "admin"
olog_password: "<olog-admin-password>"
```

### Phoebus Paths
```yaml
phoebus_install_dir: "/opt/epics-tools/lib/phoebus"
phoebus_settings_file: "{{ phoebus_install_dir }}/settings.ini"
```

### Logbook Configuration
```yaml
olog_default_logbooks: "RAPIDS"        # Default logbook for queries
olog_save_credentials: true            # Save credentials in Phoebus
```

## Usage

### In local.yml
```yaml
# Enable Olog client configuration
olog_client_config: true
olog_server_url: "http://olog.example.org:8080/Olog"
olog_default_logbooks: "RAPIDS"
```

### Run Configuration
```bash
cd /home/epics-dev/training
./vm-setup/update.sh
```

### Launch Phoebus
```bash
/opt/epics-tools/lib/phoebus/phoebus-product/phoebus.sh \
  -settings /opt/epics-tools/lib/phoebus/settings.ini
```

## What This Role Does

1. **Cleanup**: Removes all existing Olog configuration from settings.ini
2. **Factory Setup**: Configures logbook_preferences.properties with `logbook_factory=olog-es`
3. **Rebuild**: Compiles core-logbook and phoebus-product with Maven
4. **Settings**: Writes Olog connection parameters to settings.ini
5. **Defaults**: Sets default logbook and search query (last 24 hours)

## Configuration Applied

The role configures these Phoebus preferences:
```ini
# Server connection
org.phoebus.olog/olog_url=http://olog.example.com:8080/Olog
org.phoebus.olog/username=admin
org.phoebus.olog/password=<olog-admin-password>

# UI defaults
org.phoebus.logbook/default_logbooks=RAPIDS
org.phoebus.logbook/default_query=desc=*&logbooks=RAPIDS&start=24 hours&end=now
org.phoebus.logbook/search_period=24 hours
```

## Default Query Behavior

When Phoebus opens the Logbook application:
- **Calendar View**: Shows entries from default logbook, last 24 hours
- **Table View**: Shows entries from default logbook, last 24 hours
- **Query**: `desc=*&logbooks=RAPIDS&start=24 hours&end=now`

Users can manually change these defaults in the Phoebus UI.

## Rebuild Process

The role performs these Maven builds:

1. **core-logbook**: Compiles logbook core with olog-es factory (~2 minutes)
2. **phoebus-product**: Packages complete Phoebus application (~3 minutes)

Total rebuild time: ~5 minutes

## Troubleshooting

### Phoebus shows default logbooks, not mine
- Restart Phoebus after configuration
- Check settings.ini has correct Olog URL
- Verify Olog server is accessible: `curl http://server:8080/Olog/logbooks`

### Build fails during rebuild
Check Maven and Java:
```bash
which mvn
mvn --version
echo $JAVA_HOME
```

### Connection refused errors
Verify Olog server is running:
```bash
sudo systemctl status olog
curl -u admin:<olog-admin-password> http://localhost:8080/Olog
```

## References

- **Phoebus**: https://github.com/ControlSystemStudio/phoebus
- **Olog**: https://github.com/Olog/phoebus-olog
- **RAPIDS**: https://github.com/Jack-at-LNL/rapids

## License

GPL-3.0-or-later

## Author

Mauro Giacchini  
INFN Laboratori Nazionali di Legnaro  
Email: https://github.com/Jack-at-LNL/rapids/issues
