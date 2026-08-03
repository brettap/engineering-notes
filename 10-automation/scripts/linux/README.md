## Linux QEMU Guest Agent Installer

This script:

- Checks whether `qemu-guest-agent` is installed.
- Installs it when missing.
- Checks whether the service is running.
- Attempts to start the service when stopped.
- Returns an error if the service cannot be started.

### Usage

```bash
chmod +x scripts/linux/install-qemu-guest-agent.sh
./scripts/linux/install-qemu-guest-agent.sh