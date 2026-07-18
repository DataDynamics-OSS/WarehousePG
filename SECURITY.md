# Security Policy

## Reporting a vulnerability

If you find a security issue in this build/install tooling (for example,
credential leakage in build scripts, insecure defaults in the Ansible roles,
or supply-chain issues in how sources and images are fetched), please report
it privately rather than opening a public issue.

- Preferred: use GitHub's private vulnerability reporting on this repository
  ("Security" tab → "Report a vulnerability").

Issues in the WarehousePG database itself should be reported upstream to
[warehouse-pg/warehouse-pg](https://github.com/warehouse-pg/warehouse-pg).

## Notes on defaults

The Ansible playbook in `install/` ships illustrative defaults
(`gpadmin_password: "changeme"`, example IP addresses). These are placeholders:
always override them for real deployments, and never commit real inventories
or credentials back to this repository.
