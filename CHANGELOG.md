# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

### Added

- The upload API and the Pub/Sub push worker in four layers behind two ports, with unit, integration and end-to-end tests, ruff, mypy strict, import-linter, a hash-pinned lock file and a CI workflow.
- Terraform: seven modules and a `sandbox` environment (project baseline, service accounts, secret, bucket, Artifact Registry, Cloud Run, Pub/Sub push with a dead-letter topic), native tests with a mock provider, tflint and checkov.
- A local stack in `docker-compose.yml` (Pub/Sub emulator, fake Cloud Storage, the two services) and the lesson's runbook as scripts.
- `tech/`: 39 technology notes and an index, one file per language, tool, service and file format, for a reader new to all of them.
