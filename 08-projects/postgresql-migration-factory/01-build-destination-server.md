### Storage Configuration

- Storage Backend: local-zfs
- Virtual Disk Size: 200 GB
- Disk Controller: VirtIO SCSI
- I/O Thread: Enabled

#### Rationale

The VM was provisioned with a 200 GB virtual disk to provide sufficient capacity for PostgreSQL databases, backups, migration testing, Docker volumes, WAL files, and future project expansion without requiring immediate storage upgrades.