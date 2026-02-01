You are executing the **Production Readiness** skill — a comprehensive pre-deploy audit that validates security, dependencies, builds, CI/CD configuration, and Docker images before pushing to production.

## Invocation

```
/prod-ready [scope]
```

**Scopes** (optional, defaults to `full`):
- `full` — Run all checks (security + deps + builds + CI/CD + Docker)
- `security` — Only secrets scan + security headers + auth review
- `deps` — Only dependency audit (pip-audit + npm audit) and upgrades
- `build` — Only build verification (frontend + backend)
- `cicd` — Only CI/CD config validation (Cloud Build, GitHub Actions, Artifact Registry)
- `docker` — Only Dockerfile validation and image build test

## Execution Protocol

### Phase 1: Discovery

Automatically detect the project structure:

1. **Find project root**: Look for `.git`, `package.json`, `requirements.txt`, `Dockerfile`, `CLAUDE.md`
2. **Detect stack**:
   - Python backend? Check for `requirements.txt`, `Pipfile`, `pyproject.toml`
   - Node frontend? Check for `package.json`, `vite.config.*`, `next.config.*`
   - Docker? Check for `Dockerfile`, `docker-compose.yml`
   - CI/CD? Check for `cloudbuild.yaml`, `.github/workflows/`, `Jenkinsfile`
3. **Read CLAUDE.md** if present — use it for project context
4. **Determine active branch** and uncommitted changes via `git status`

### Phase 2: Security Audit

Launch parallel sub-agents for each security domain:

#### 2a. Secrets Scan
Search ALL files (including untracked) for:
- API keys: `AIza[0-9A-Za-z\-_]{35}`, `sk-[a-zA-Z0-9]{20,}`, `ghp_[0-9a-zA-Z]{36}`
- AWS keys: `AKIA[0-9A-Z]{16}`
- Private keys: `-----BEGIN (RSA |EC )?PRIVATE KEY-----`
- Connection strings with passwords: `://[^:]+:[^@]+@`
- Hardcoded JWT secrets, passwords, tokens in source code
- Firebase credentials embedded in Dockerfiles or CI configs

**Exclude**: `.env` files (local dev), test fixtures with mock data, documentation references

**Report**: File path, line number, pattern matched, severity (CRITICAL if real key, LOW if test mock)

#### 2b. Security Headers
Check for standard security headers in:
- **Backend**: Flask/Express/Django middleware — CSP, X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy
- **Frontend**: nginx.conf, next.config.js, or CDN config — same headers plus Permissions-Policy
- **Missing HSTS**: Flag if HTTPS is used but HSTS header is missing

#### 2c. Authentication Review
- Verify auth middleware is applied to all routes (check for unprotected endpoints)
- Check CORS configuration — flag if localhost is in production CORS origins
- Verify JWT/session secret is loaded from environment, not hardcoded
- Check rate limiting is configured

#### 2d. .gitignore Validation
- Verify `.env`, credentials, service account keys, private keys are gitignored
- Check if any gitignored files are actually tracked: `git ls-files -i --exclude-standard`
- Flag common misses: `.env.local`, `*.pem`, `credentials/`, `serviceAccountKey.json`

### Phase 3: Dependency Audit

#### 3a. Python Dependencies
```bash
pip-audit                    # Check for CVEs
pip list --outdated          # Find available upgrades
```

For each vulnerability:
- **Patch upgrade available** (e.g., 3.1.0 → 3.1.1): Auto-upgrade, run tests, verify
- **Minor upgrade available** (e.g., 2.5.0 → 2.6.3): Upgrade if transitive dep, test
- **Major upgrade needed** (e.g., 5.0.1 → 6.0.0): Document but DO NOT auto-upgrade — flag for manual review
- **No fix available**: Document with CVE ID

Update `requirements.txt` and `requirements-prod.txt` (if exists) with safe upgrades.

#### 3b. Node Dependencies
```bash
npm audit                          # Check for vulnerabilities
npm audit fix                      # Auto-fix safe upgrades
npm audit --audit-level=high       # Check remaining high/critical
```

Categorize results:
- **Auto-fixable**: Apply `npm audit fix`
- **Upstream/transitive**: Document (e.g., Firebase SDK issues)
- **Breaking changes**: Flag for manual review

#### 3c. Version Compatibility
- Verify Dockerfile base image versions match local/CI versions
- Python: Compare Dockerfile FROM, CI setup-python, requirements header
- Node: Compare Dockerfile FROM, CI setup-node, package.json engines
- Flag mismatches

### Phase 4: Build Verification

#### 4a. Backend
```bash
# Python syntax check
python -m py_compile app.py  # or main entry point

# Run tests
pytest tests/unit -q --no-cov  # Unit tests only (fast)

# If Docker available: build image
docker build -t backend:audit ./backend
```

#### 4b. Frontend
```bash
# TypeScript check
npx tsc --noEmit

# Build
npm run build

# Tests
npm test

# Bundle size report
ls -la dist/assets/  # Report JS/CSS sizes
```

### Phase 5: CI/CD Validation

#### 5a. Registry Migration
- Flag any `gcr.io` usage (deprecated) — should be Artifact Registry (`docker.pkg.dev`)
- Verify all image paths are consistent across:
  - Cloud Build configs
  - GitHub Actions workflows
  - Deploy scripts
  - docker-compose files

#### 5b. Substitution Variables
- Verify no secrets are hardcoded in CI configs
- All sensitive values should use:
  - Cloud Build: `$_VARIABLE` substitutions or `--set-secrets`
  - GitHub Actions: `${{ secrets.* }}`
  - Docker: `ARG` + `--build-arg` (never `ENV` for secrets)
- Verify all required substitutions are documented or have defaults

#### 5c. Deploy Configuration
- Verify backend deploys before frontend (frontend may need backend URL)
- Check CORS origins don't include localhost in production deploy
- Verify health check endpoints are configured
- Check resource limits are reasonable (memory, CPU, instances, timeout)
- Verify `--set-secrets` references match Secret Manager entries

### Phase 6: Docker Validation

#### 6a. Dockerfile Best Practices
- Multi-stage build? (builder → runtime)
- Non-root user? (`USER` directive)
- `.dockerignore` exists and excludes secrets, node_modules, venv, .git?
- `apt-get` caches cleaned? (`rm -rf /var/lib/apt/lists/*`)
- HEALTHCHECK configured?
- No `COPY . .` before dependency install? (layer caching)

#### 6b. Image Build Test (if Docker available)
```bash
docker build -t app:audit .
# Verify image builds without errors
# Check image size
docker images app:audit --format "{{.Size}}"
```

#### 6c. Container Smoke Test (if Docker available)
```bash
docker run -d --name audit-test -p 8080:8080 -e ENV=production app:audit
sleep 5
curl -f http://localhost:8080/health
docker stop audit-test && docker rm audit-test
```

## Output Format

Generate a structured report:

```markdown
# Production Readiness Report

**Project**: <name>
**Branch**: <branch>
**Date**: <date>
**Scope**: <full|security|deps|build|cicd|docker>

## Summary

| Category | Status | Issues Found | Fixed |
|----------|--------|-------------|-------|
| Security | PASS/WARN/FAIL | N | N |
| Dependencies | PASS/WARN/FAIL | N | N |
| Build | PASS/FAIL | N | N |
| CI/CD | PASS/WARN/FAIL | N | N |
| Docker | PASS/WARN/SKIP | N | N |

## Findings

### [CRITICAL] <title>
- **Location**: file:line
- **Description**: ...
- **Fix Applied**: Yes/No
- **Action Required**: ...

### [HIGH] <title>
...

### [MEDIUM] <title>
...

### [LOW] <title>
...

## Dependency Audit

### Python (pip-audit)
| Package | Current | Fixed To | CVEs Resolved | Status |
|---------|---------|----------|---------------|--------|

### Remaining Vulnerabilities
| Package | CVE | Severity | Reason Can't Fix |
|---------|-----|----------|-----------------|

### Node (npm audit)
| Severity | Count | Auto-fixed | Remaining |
|----------|-------|------------|-----------|

## Changes Made
- [ ] file1: description
- [ ] file2: description

## Manual Actions Required
1. ...
2. ...
```

## Behavior Rules

1. **Never break working code** — run tests after every change. If tests fail, revert.
2. **Conservative upgrades** — only auto-apply patch-level upgrades. Flag major/minor for review.
3. **Don't modify application logic** — only touch config, dependencies, and security settings.
4. **Preserve existing patterns** — if the project uses `requirements-prod.txt` separately, update both.
5. **Create a branch** if not already on a feature branch — never modify `main` directly.
6. **Report, don't guess** — if Docker isn't available, skip image builds and report "SKIP".
7. **Use sub-agents** — launch parallel Task agents for independent checks to maximize speed.
8. **Read CLAUDE.md first** — respect project-specific conventions documented there.
9. **Cite everything** — every finding must include file:line references.
10. **Idempotent** — running the skill twice should produce the same result (no double-upgrades).

## Multi-Agent Strategy

Use the Task tool to parallelize:

```
Message 1 (parallel):
  - Agent A (Explore): Security headers + auth middleware scan
  - Agent B (Explore): Secrets scan across all files
  - Agent C (Explore): CI/CD config validation
  - Agent D (Explore): Dockerfile best practices review

Message 2 (sequential, after agents return):
  - Apply safe dependency upgrades
  - Run tests
  - Generate report
```

Use `model: "sonnet"` for scanning agents, default for synthesis.

## Examples

### Full audit
```
/prod-ready
```
Runs all phases. Creates branch if on main. Applies safe fixes. Generates full report.

### Security only
```
/prod-ready security
```
Runs only Phase 2 (secrets scan, headers, auth, gitignore). No dependency changes.

### Pre-deploy quick check
```
/prod-ready build
```
Runs only Phase 4 (TypeScript check, tests, build). Verifies nothing is broken.

### Dependency refresh
```
/prod-ready deps
```
Runs pip-audit + npm audit. Applies safe patches. Reports remaining vulnerabilities.
