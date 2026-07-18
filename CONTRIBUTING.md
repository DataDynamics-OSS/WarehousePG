# Contributing

Thanks for your interest in improving the WarehousePG build and install
tooling. Contributions are welcome via GitHub pull requests.

## Ground rules

- **Scope**: this repository covers build, packaging, and installation tooling
  only. Changes to the WarehousePG database itself belong upstream at
  [warehouse-pg/warehouse-pg](https://github.com/warehouse-pg/warehouse-pg).
- **No secrets**: never commit credentials, tokens, private keys, real host
  inventories, or customer-specific configuration. The Ansible inventory and
  passwords in this repository are illustrative placeholders and must stay
  that way. CI runs a secret scan on every push.
- **Reproducibility**: builds must stay reproducible. Pin sources to tags or
  commit SHAs (as done for PXF) rather than moving branches.

## Workflow

1. Fork the repository and create a topic branch.
2. Make your change. Shell scripts should pass `shellcheck`; Ansible changes
   should pass `ansible-playbook --syntax-check`.
3. Open a pull request describing what the change does and why. If it alters
   build output (paths, versions, bundled extensions), note that explicitly.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
