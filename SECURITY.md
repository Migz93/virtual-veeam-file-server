<!-- shared: structure — headings kept in sync across Migz93 self-hosted apps, content is app-specific -->

# Security Policy

## Reporting A Vulnerability

Please do not open a public GitHub issue for security-sensitive problems.

If you find a vulnerability in Virtual Veeam File Server, report it privately through GitHub's private vulnerability reporting flow for this repository if it is enabled. If that is not available, contact the maintainer directly through a private channel before disclosing details publicly.

When reporting an issue, please include:

- a short description of the problem
- the affected version or commit if known
- clear reproduction steps
- the expected impact
- any suggested mitigation if you have one

## Disclosure Expectations

- Please allow time for the issue to be investigated and fixed before public disclosure.
- I will try to acknowledge reports promptly and keep you updated on the status.
- Once a fix is available, the goal is to disclose the issue responsibly with enough detail for users to protect themselves.

## Scope

Security reports are especially helpful for issues involving:

- SSH authentication or credential handling
- token, password, or key exposure
- privilege escalation
- remote code execution
- container or deployment security
- unsafe default configuration
- Veeam component persistence behavior

## Supported Versions

Virtual Veeam File Server is still early in development. Until a stable release policy is documented, security fixes are handled on the latest supported code line.

## Container Security Notes

- This project is unofficial and not produced by Veeam.
- No default password is baked into the image.
- No private SSH keys are baked into or required by the image.
- Passwords are not printed to logs.
- SSH key authentication is recommended.
- The managed SSH user has passwordless sudo so VBR can deploy and manage Linux components.
- The container does not require Docker `privileged: true`, but it does require host cgroup access for systemd.
- Source-data mounts are user-controlled. Do not mount data over `/opt`, because `/opt/veeam` is reserved for Veeam components.

## Security Scanning

Useful local checks:

| What you're scanning | Command |
|---|---|
| Shell scripts | `shellcheck scripts/*.sh tests/*.sh` |
| Docker image build | `docker build -t virtual-veeam-file-server:test .` |
| Container behavior | `IMAGE_NAME=virtual-veeam-file-server:test tests/run-container-tests.sh` |
