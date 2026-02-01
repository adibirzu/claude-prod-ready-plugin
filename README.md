# claude-prod-ready-plugin

A Claude Code plugin that runs comprehensive production readiness audits before you deploy. It checks security, dependencies, builds, CI/CD configs, and Docker images — then generates a structured report with findings and auto-applied fixes.

## What It Does

| Phase | Checks |
|-------|--------|
| **Security** | Secrets scan, security headers, auth middleware coverage, CORS validation, .gitignore audit |
| **Dependencies** | `pip-audit` + `npm audit`, CVE detection, safe patch upgrades, version compatibility |
| **Build** | Python syntax, TypeScript check, test suite, frontend build, bundle size |
| **CI/CD** | Registry migration (gcr.io deprecation), substitution variables, deploy ordering, secret management |
| **Docker** | Multi-stage builds, non-root user, .dockerignore, layer caching, HEALTHCHECK, image build test |

## Installation

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- `python3` available in PATH (used by the installer)

### Install

```bash
git clone https://github.com/adibirzu/claude-prod-ready-plugin.git
cd claude-prod-ready-plugin
bash install.sh
```

Then **restart Claude Code** to load the plugin.

### Uninstall

```bash
bash install.sh --uninstall
```

## Usage

Inside any project directory in Claude Code:

```
/prod-ready              # Full audit (all phases)
/prod-ready security     # Secrets scan, headers, auth, .gitignore
/prod-ready deps         # pip-audit + npm audit, safe upgrades
/prod-ready build        # TypeScript, tests, build verification
/prod-ready cicd         # Cloud Build, GitHub Actions, Artifact Registry
/prod-ready docker       # Dockerfile best practices, image build test
```

## Scopes

| Scope | Phases Run | Modifies Code? |
|-------|-----------|----------------|
| `full` (default) | All 6 phases | Yes — safe dependency patches |
| `security` | Phase 2 only | No |
| `deps` | Phase 3 only | Yes — patch upgrades to requirements/package.json |
| `build` | Phase 4 only | No |
| `cicd` | Phase 5 only | No |
| `docker` | Phase 6 only | No |

## Output

The plugin generates a structured markdown report:

```
# Production Readiness Report

**Project**: my-app
**Branch**: feature/deploy-prep
**Date**: 2026-02-01

## Summary

| Category     | Status | Issues Found | Fixed |
|-------------|--------|-------------|-------|
| Security     | PASS   | 0           | 0     |
| Dependencies | WARN   | 14          | 8     |
| Build        | PASS   | 0           | 0     |
| CI/CD        | WARN   | 2           | 2     |
| Docker       | SKIP   | -           | -     |

## Findings
### [CRITICAL] Hardcoded API key in Dockerfile
- **Location**: backend/Dockerfile:23
- **Fix Applied**: Yes
...
```

## Supported Stacks

The plugin auto-detects your project stack:

- **Python**: Flask, Django, FastAPI — checks `requirements.txt`, `Pipfile`, `pyproject.toml`
- **Node.js**: React, Next.js, Vue, Express — checks `package.json`, build configs
- **Docker**: Dockerfile, docker-compose.yml
- **CI/CD**: Cloud Build (`cloudbuild.yaml`), GitHub Actions (`.github/workflows/`), Jenkinsfile

## Behavior Rules

1. **Never breaks working code** — runs tests after every change, reverts on failure
2. **Conservative upgrades** — only auto-applies patch-level dependency upgrades
3. **Doesn't modify application logic** — only touches config, deps, and security settings
4. **Creates a branch** if on main — never modifies main directly
5. **Reports, doesn't guess** — if Docker isn't available, skips and reports "SKIP"
6. **Idempotent** — running twice produces the same result

## Plugin Structure

```
claude-prod-ready-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── commands/
│   └── prod-ready.md        # Skill prompt (the audit logic)
├── install.sh               # Installer/uninstaller
├── README.md                # This file
├── ARCHITECTURE.md           # Technical architecture
└── LICENSE                  # MIT License
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details on how the plugin works.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-check`)
3. Edit `commands/prod-ready.md` to add or modify audit checks
4. Test by running `bash install.sh` and invoking `/prod-ready` in a project
5. Submit a pull request

### Adding a New Check

Checks are defined in `commands/prod-ready.md` as phases. To add a new check:

1. Add it under the appropriate phase (Security, Dependencies, Build, CI/CD, Docker)
2. Include the specific commands or patterns to look for
3. Define the severity level (CRITICAL, HIGH, MEDIUM, LOW)
4. Describe what to report and whether auto-fix is safe

### Adding a New Scope

1. Add the scope name to the **Scopes** list at the top of `prod-ready.md`
2. Define which phases it runs
3. Update the Examples section

## License

[MIT](LICENSE)
