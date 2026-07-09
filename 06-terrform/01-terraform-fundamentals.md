What Terraform is
	Terraform is an agnostic IaC configuration method that allows the creation of resources via describing the resources by scripting (HCL).

Declarative vs procedural
	Terraform is declarative. It allows you to define your resources step by step.
	Focuses on:
	End state
	Configuration files
	High state awareness and drift management
	Allows for self-healing and the re-creation of resources based on the config files.

	Procedural methods (Ansible, Bash, Python) focuses on execution steps via scripts or programs.
	Unaware of state
	Re-runs steps, which can cause issues/errors

Desired state
	Terraform checks for desired state to ensure resources match the description provided.

Providers
	AWS; Azure; GCP.

Resources
	Identity
	Compute
	Memory
	Storage
	Network
	Operating System
	Security
	Monitoring

Attributes
 
