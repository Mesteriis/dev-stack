# Support

## Getting Help

For setup, contribution or usage questions, open a GitHub Discussion or issue if the repository enables it.

For bug reports, use the bug report template and include:

- macOS version
- Swift version
- Docker runtime
- active Docker context
- whether the problem is local-only or tied to a saved runtime target
- the affected profile name and whether it was the current profile or another active profile
- whether the issue involved the single-instance lock or a relaunch
- whether the issue involves tunnels, compose or profile switching
- whether managed variables, `.env` files or Keychain secrets were involved
- whether the project was detected from PyCharm or VS Code
- any generated report that helps, such as compose preview, logs, metrics, volume or remote-file output
- reproduction steps

## What This Project Supports

- the latest state of the `main` branch
- macOS developer workflows centered around remote Docker access and local compose switching
- the built-in variable manager and Keychain-backed secret manager used by compose profiles
- multi-file compose profiles and project-relative bind mounts for dev workflows
- startup activation prompts based on supported IDE project detection

## What This Project Does Not Promise

- Windows or Linux support
- signed production distributions
- compatibility with every possible compose-file dialect
- production-grade orchestration or prod-safety guardrails
