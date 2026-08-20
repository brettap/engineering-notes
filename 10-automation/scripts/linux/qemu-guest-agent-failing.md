# QEMU Guest Agent fails to start after installation on Ubuntu

Symptoms

systemctl status qemu-guest-agent shows dependency failure.
Journal contains:
Expecting device /dev/virtio-ports/org.qemu.guest_agent.0
Dependency failed for qemu-guest-agent.service

Root Cause

The QEMU Guest Agent device was not present because the VM had not been restarted after enabling the Guest Agent in Proxmox.

Resolution

Enable QEMU Guest Agent in Proxmox.
Perform a full VM shutdown and start (not just restarting the service).

Verify:

systemctl status qemu-guest-agent
qm agent <vmid> ping