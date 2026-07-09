Issue

Terraform-created VM booted to the UEFI shell instead of the Windows installer.

Investigation
Verified Proxmox API authentication.
Compared qm config output of a working manually created VM with the Terraform-created VM.
Updated CPU, machine type, EFI configuration, and TPM settings.
Confirmed the Windows Server ISO was valid by testing it in a manually created VM.
Resolution

The VM required manually selecting the CD-ROM as the initial boot device. Once selected, Windows Server Setup launched immediately and installation proceeded normally.

Lesson Learned

A successful Terraform deployment does not guarantee identical firmware boot behavior to a manually created Proxmox VM. Comparing qm config output between a known-good VM and an IaC-provisioned VM is an effective troubleshooting technique.
