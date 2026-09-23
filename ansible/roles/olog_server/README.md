# RAPIDS - Olog Server Role

## Description

Ansible role for deploying Olog electronic logbook server in the RAPIDS (Rapid Automated Production Infrastructure Deployment System) architecture. This role provides complete automation for Olog 5.x installation, including MongoDB, ElasticSearch, and the Olog service itself.

**Institution:** INFN Laboratori Nazionali di Legnaro  
**Author:** Mauro Giacchini  
**Project:** RAPIDS

## Features

- **Declarative Architecture**: Running `./vm-setup/update.sh` brings system to exact state defined in `local.yml`
- **Automatic CPU Detection**: MongoDB version auto-selected based on AVX instruction support
- **Complete Cleanup**: Removes previous installations before deploying fresh configuration
- **Source Build**: Builds Olog 5.x from source using Maven (no pre-built binaries available)
- **Initial Data Seeding**: Creates logbooks and tags from `local.yml` via REST API
- **Automated Backups**: Daily backup with configurable retention
- **RAPIDS Compliant**: Follows RAPIDS standard paths (`/opt/epics-tools`)

## Requirements

- **Operating System**: AlmaLinux 9 or RHEL 9
- **Ansible**: 2.9 or later
- **Java**: OpenJDK 17+ (provided by epics-tools role)
- **Maven**: 3.6+ (provided by epics-tools role)
- **Network**: Internet access for package downloads and git clone

## Dependencies

This role should be run after the `epics-tools` role which provides Java and Maven.

## Role Variables

### Installation Paths
```yaml
olog_version: "5.1.2"                      # Olog version to build
olog_install_dir: "/opt/epics-tools/olog"  # Installation directory
olog_data_dir: "/var/lib/olog"             # Data directory
olog_log_dir: "/var/log/olog"              # Log directory
```

### Service Configuration
```yaml
olog_port: 8080                            # HTTP port
olog_admin_user: "admin"                   # Administrator username
olog_admin_password: "<olog-admin-password>"           # Administrator password
```

### Database Configuration
```yaml
# MongoDB (version auto-detected based on CPU)
olog_mongodb_port: 27017
olog_mongodb_database: "olog"

# ElasticSearch
olog_elasticsearch_cluster_name: "olog-cluster"
olog_elasticsearch_http_port: 9200
```

### Initial Data
```yaml
olog_seed_initial_data: true
olog_initial_logbooks:
  - name: "RAPIDS"
    owner: "olog-logs"
    state: "Active"
    description: "RAPIDS project activities"

olog_initial_tags:
  - name: "critical"
    description: "Critical issue"
  - name: "routine"
    description: "Routine activity"
```

### Backup Configuration
```yaml
olog_enable_backup: true
olog_backup_dir: "/backup/olog"
olog_backup_retention_days: 30
```

## Usage

### In local.yml
```yaml
# Activate Olog server installation
olog_server: true
olog_server_host: olog.example.com
olog_server_port: 8080

# Configure initial logbooks
olog_initial_logbooks:
  - name: "Operations"
    owner: "olog-logs"
    state: "Active"
    description: "Operations logbook"

# Configure initial tags
olog_initial_tags:
  - name: "maintenance"
    description: "Maintenance activity"
  - name: "alarm"
    description: "Alarm condition"
```

### Run Installation
```bash
cd /home/epics-dev/training
./vm-setup/update.sh
```

## Architecture

### Components

1. **MongoDB** (4.4+ or 7.0)
   - Stores attachments and log metadata
   - Version auto-selected based on CPU AVX support
   - Non-AVX systems use MongoDB 4.4 from RHEL 8 repository

2. **ElasticSearch** (8.x)
   - Indexes log entries for fast search
   - Security features disabled for internal deployment
   - Single-node configuration

3. **Olog Service** (5.1.2)
   - Spring Boot application
   - Built from source using Maven
   - REST API for log entry management

### Directory Structure
```
/opt/epics-tools/olog/          # Installation
├── config/
│   └── application.properties  # Service configuration
└── olog-service.jar            # Application JAR

/var/lib/olog/                  # Data
└── attachments/                # Log attachments

/var/log/olog/                  # Logs

/backup/olog/                   # Backups
└── YYYYMMDD_HHMMSS/            # Daily backup snapshots
```

### Network Ports

- `8080`: Olog HTTP service
- `9200`: ElasticSearch HTTP
- `27017`: MongoDB

## Cleanup Behavior

The role implements complete cleanup before installation:

- **Removed**: Services, configuration files, installation directories
- **Preserved**: ElasticSearch/MongoDB data (contains keystores)
- **Optional**: User/group removal (disabled by default for safety)

## Building from Source

Olog 5.x releases are source-only. The role automatically:

1. Clones repository from GitHub
2. Checks out specified version tag
3. Builds using Maven (`mvn clean install -DskipTests`)
4. Extracts JAR from build output
5. Deploys to installation directory

Build time: 5-10 minutes on first run (Maven downloads dependencies)

## Monitoring

### Service Status
```bash
sudo systemctl status olog
sudo systemctl status elasticsearch
sudo systemctl status mongod
```

### Logs
```bash
sudo journalctl -u olog -f
sudo tail -f /var/log/olog/olog.log
```

### Health Check
```bash
curl -u admin:<olog-admin-password> http://localhost:8080/Olog
```

## Troubleshooting

### MongoDB won't start on non-AVX CPU
The role automatically detects this and installs MongoDB 4.4 from RHEL 8 repository.

### ElasticSearch permission errors
Role automatically fixes permissions and removes SSL keystore passwords.

### Olog build fails
Check Maven and Java installation from epics-tools role:
```bash
which mvn
mvn --version
echo $JAVA_HOME
```

## References

- **Olog Project**: https://github.com/Olog/phoebus-olog
- **RAPIDS Project**: https://github.com/Jack-at-LNL/rapids
- **MongoDB Documentation**: https://docs.mongodb.com
- **ElasticSearch Documentation**: https://www.elastic.co/guide

## License

GPL-3.0-or-later

## Author

Mauro Giacchini  
INFN Laboratori Nazionali di Legnaro  
Contact: https://github.com/Jack-at-LNL/rapids/issues
