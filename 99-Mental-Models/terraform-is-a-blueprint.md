# Terraform is a Blueprint

Terraform does not tell Proxmox how to build a VM.

Terraform describes what the finished VM should look like.

The provider translates the description into API calls.

Terraform compares:

Desired State

vs

Current State

and generates an execution plan.

Terraform is like an empty balloon. Every resource attribute adds another puff of air until the VM description is complete.
