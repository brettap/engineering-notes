## Session: Ubuntu DevOps02 VM Creation

### Objective
Create the dedicated Linux server that will host the PostgreSQL Migration Factory.

### Work Completed
- Created Ubuntu Server VM named `ubuntu-devops02`
- Assigned 8 GB RAM to support PostgreSQL caching and future DevOps tooling
- Reserved the VM as the dedicated Linux platform for PostgreSQL, Docker, Python, Ansible, Terraform, and migration scripts
- Kept database services isolated from the Windows Domain Controllers following separation-of-services best practices

### Outcome
The virtual machine is ready for hardware verification and Ubuntu Server installation.