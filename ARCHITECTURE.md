# Architecture

Technical documentation for the `prod-ready` Claude Code plugin.

## How Claude Code Plugins Work

Claude Code plugins are prompt-based skills. When a user invokes `/prod-ready`, Claude Code loads `commands/prod-ready.md` as a system-level instruction that guides the AI through a structured audit workflow. There is no traditional code execution — the "logic" is the prompt itself, which Claude follows step by step using its built-in tools (file reads, bash commands, grep, agents).

### Plugin Loading

```
~/.claude/plugins/
├── cache/local-plugins/prod-ready/1.0.0/   # Claude Code reads from here
│   ├── .claude-plugin/plugin.json
│   └── commands/prod-ready.md
├── repos/prod-ready-plugin/                 # Source copy
└── installed_plugins.json                   # Plugin registry
```

The installer (`install.sh`) copies files to both `cache/` (runtime) and `repos/` (reference), then registers the plugin in `installed_plugins.json` and enables it in `~/.claude/settings.json`.

## Execution Flow

```
User invokes /prod-ready [scope]
         │
         ▼
┌─────────────────────┐
│  Phase 1: Discovery │  Detect stack, read CLAUDE.md, check git status
└────────┬────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  Phase 2-6: Parallel Scanning (via Task sub-agents) │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐                │
│  │  Agent A:     │  │  Agent B:     │                │
│  │  Security     │  │  Secrets      │                │
│  │  Headers +    │  │  Scan         │                │
│  │  Auth Review  │  │              │                │
│  └──────────────┘  └──────────────┘                │
│  ┌──────────────┐  ┌──────────────┐                │
│  │  Agent C:     │  │  Agent D:     │                │
│  │  CI/CD        │  │  Docker       │                │
│  │  Validation   │  │  Best         │                │
│  │              │  │  Practices    │                │
│  └──────────────┘  └──────────────┘                │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│  Sequential: Dependency Upgrades                     │
│  pip-audit → safe patches → run tests → verify      │
│  npm audit → npm audit fix → verify                 │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│  Report Generation                                   │
│  Structured markdown with findings, fixes, actions  │
└─────────────────────────────────────────────────────┘
```

## Phase Details

### Phase 1: Discovery

Runs first, always. Determines what subsequent phases need to check.

**Inputs**: File system scan
**Outputs**: Stack type (Python/Node/Docker/CI), project root, branch name, CLAUDE.md context

### Phase 2: Security Audit

Four parallel sub-checks:

| Sub-check | What it scans | Patterns |
|-----------|--------------|----------|
| 2a. Secrets | All files including untracked | API key regexes, private keys, connection strings |
| 2b. Headers | Middleware configs, nginx.conf | CSP, HSTS, X-Frame-Options, X-Content-Type-Options |
| 2c. Auth | Route definitions, middleware | Unprotected endpoints, CORS localhost, hardcoded secrets |
| 2d. .gitignore | Git tracked files vs ignore rules | Tracked secrets, missing ignore patterns |

**Severity mapping**:
- CRITICAL: Real API key or private key in source
- HIGH: Missing auth on endpoint, localhost in production CORS
- MEDIUM: Missing security header
- LOW: Test mock data matching a secret pattern

### Phase 3: Dependency Audit

Sequential (modifies files).

**Python path**: `pip-audit` → categorize by fix type → apply patch upgrades → `pip install` → `pytest` → update requirements files

**Node path**: `npm audit` → `npm audit fix` → check remaining → report

**Upgrade policy**:
| Upgrade Type | Action |
|-------------|--------|
| Patch (x.y.Z) | Auto-apply |
| Minor (x.Y.z) | Apply for transitive deps only |
| Major (X.y.z) | Document, flag for manual review |
| No fix | Document with CVE ID |

### Phase 4: Build Verification

**Backend**: `python -m py_compile` → `pytest` (unit only, `--no-cov`)
**Frontend**: `npx tsc --noEmit` → `npm run build` → `npm test` → bundle size report

### Phase 5: CI/CD Validation

| Check | What it flags |
|-------|--------------|
| Registry | `gcr.io` usage (deprecated, should be Artifact Registry) |
| Consistency | Image path mismatches between CI configs, deploy scripts, compose files |
| Secrets | Hardcoded values in CI configs instead of substitution variables |
| Deploy order | Frontend deploying before backend |
| CORS | Localhost in production CORS origins |
| Resources | Missing health checks, unreasonable limits |

### Phase 6: Docker Validation

| Check | Best Practice |
|-------|--------------|
| Multi-stage | Separate builder and runtime stages |
| Non-root | `USER` directive present |
| .dockerignore | Excludes .git, node_modules, venv, secrets |
| Layer caching | Dependencies installed before COPY . . |
| apt cleanup | `rm -rf /var/lib/apt/lists/*` after install |
| HEALTHCHECK | Configured in Dockerfile |
| Image build | Builds without errors (if Docker available) |
| Smoke test | Container starts and responds to health check |

## Multi-Agent Strategy

The plugin instructs Claude Code to use its Task tool for parallelism:

- **Scanning agents** (Explore type, `model: "sonnet"`): Fast, read-only checks run in parallel
- **Synthesis agent** (default model): Collects results, applies fixes sequentially, generates report

This means a full audit touches the codebase with 4+ parallel readers before a single writer applies changes.

## Scope Filtering

When a scope is specified (e.g., `/prod-ready security`), only the corresponding phases execute:

| Scope | Phases |
|-------|--------|
| `full` | 1 → 2 → 3 → 4 → 5 → 6 |
| `security` | 1 → 2 |
| `deps` | 1 → 3 |
| `build` | 1 → 4 |
| `cicd` | 1 → 5 |
| `docker` | 1 → 6 |

Phase 1 (Discovery) always runs to establish context.

## Extension Points

### Adding a new phase

1. Define the phase in `commands/prod-ready.md` after the existing phases
2. Add it to the scope table
3. Add the scope keyword to the invocation section
4. Define which agents run it (parallel or sequential)

### Adding checks to an existing phase

1. Add the check under the appropriate phase section in `commands/prod-ready.md`
2. Include: what to scan, regex/patterns, severity, recommended fix
3. If auto-fixable, describe the fix clearly enough for Claude to apply it

### Changing upgrade policy

The upgrade policy (patch=auto, minor=conditional, major=manual) is defined in Phase 3. Modify the bullet points under "For each vulnerability" to change behavior.

## File Reference

| File | Purpose | Modified at runtime? |
|------|---------|---------------------|
| `.claude-plugin/plugin.json` | Plugin metadata, version | No |
| `commands/prod-ready.md` | Skill prompt — all audit logic | No |
| `install.sh` | Installer/uninstaller | No |
| `README.md` | User documentation | No |
| `ARCHITECTURE.md` | This file | No |
| `LICENSE` | MIT license | No |
