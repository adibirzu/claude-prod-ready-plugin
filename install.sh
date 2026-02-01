#!/bin/bash
# Production Readiness Plugin Installer v1.0.0
# Installs the prod-ready plugin for Claude Code and enables it in settings.
#
# Usage:
#   bash install.sh              # Install the plugin
#   bash install.sh --uninstall  # Remove the plugin

set -e

PLUGIN_NAME="prod-ready"
PLUGIN_VERSION="1.0.0"
PLUGIN_DIR="$HOME/.claude/plugins/repos/${PLUGIN_NAME}-plugin"
CACHE_DIR="$HOME/.claude/plugins/cache/local-plugins/${PLUGIN_NAME}"
SETTINGS_FILE="$HOME/.claude/settings.json"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

uninstall() {
    echo "Uninstalling ${PLUGIN_NAME} plugin..."
    [ -d "$PLUGIN_DIR" ] && rm -rf "$PLUGIN_DIR" && info "Removed $PLUGIN_DIR"
    [ -d "$CACHE_DIR" ] && rm -rf "$CACHE_DIR" && info "Removed cache"

    if [ -f "$SETTINGS_FILE" ] && command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE', 'r') as f:
        s = json.load(f)
    ep = s.get('enabledPlugins', {})
    ep.pop('${PLUGIN_NAME}@local-plugins', None)
    s['enabledPlugins'] = ep
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    print('Settings updated')
except Exception as e:
    print(f'Could not update settings: {e}', file=sys.stderr)
"
    fi
    info "${PLUGIN_NAME} plugin uninstalled. Restart Claude Code."
    exit 0
}

# Handle --uninstall flag
[ "${1:-}" = "--uninstall" ] && uninstall

echo ""
echo "=== Installing ${PLUGIN_NAME} Plugin v${PLUGIN_VERSION} ==="
echo ""

# Step 1: Verify source files exist
step "Verifying source files..."
REQUIRED_FILES=(".claude-plugin/plugin.json" "commands/prod-ready.md")
for f in "${REQUIRED_FILES[@]}"; do
    [ ! -f "$SCRIPT_DIR/$f" ] && error "Missing required file: $f (run from plugin directory)"
done
info "Source files verified"

# Step 2: Create plugin directory
step "Creating plugin directory..."
mkdir -p "$PLUGIN_DIR/.claude-plugin"
mkdir -p "$PLUGIN_DIR/commands"
info "Plugin directories created"

# Step 3: Copy plugin files
step "Copying plugin files..."
cp "$SCRIPT_DIR/.claude-plugin/plugin.json" "$PLUGIN_DIR/.claude-plugin/"
cp "$SCRIPT_DIR/commands/prod-ready.md" "$PLUGIN_DIR/commands/"

for f in README.md install.sh; do
    [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$PLUGIN_DIR/"
done
info "Plugin files copied to $PLUGIN_DIR"

# Step 4: Set up cache directory (Claude Code reads from here)
step "Setting up cache..."
CACHE_VERSION_DIR="$CACHE_DIR/$PLUGIN_VERSION"
mkdir -p "$CACHE_VERSION_DIR/.claude-plugin"
mkdir -p "$CACHE_VERSION_DIR/commands"
cp "$SCRIPT_DIR/.claude-plugin/plugin.json" "$CACHE_VERSION_DIR/.claude-plugin/"
cp "$SCRIPT_DIR/commands/prod-ready.md" "$CACHE_VERSION_DIR/commands/"
for f in README.md install.sh; do
    [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$CACHE_VERSION_DIR/"
done
info "Cache populated at $CACHE_VERSION_DIR"

# Step 5: Update installed_plugins.json
step "Registering plugin..."
if command -v python3 &>/dev/null; then
    mkdir -p "$(dirname "$INSTALLED_FILE")"
    [ -f "$INSTALLED_FILE" ] && cp "$INSTALLED_FILE" "$INSTALLED_FILE.backup"
    python3 -c "
import json, os
from datetime import datetime, timezone

installed_file = '$INSTALLED_FILE'
plugin_name = '${PLUGIN_NAME}@local-plugins'
cache_path = '$CACHE_VERSION_DIR'
version = '$PLUGIN_VERSION'
home = os.path.expanduser('~')

if os.path.exists(installed_file):
    with open(installed_file, 'r') as f:
        data = json.load(f)
else:
    data = {'plugins': {}}

plugins = data.setdefault('plugins', {})
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')

plugins[plugin_name] = [{
    'scope': 'project',
    'installPath': cache_path,
    'version': version,
    'installedAt': now,
    'lastUpdated': now,
    'projectPath': home
}]

with open(installed_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('Plugin registered in installed_plugins.json')
"
    info "Plugin registered"
else
    warn "python3 not found. Manually register the plugin in $INSTALLED_FILE"
fi

# Step 6: Enable in settings.json
step "Enabling plugin..."
if command -v python3 &>/dev/null; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    [ -f "$SETTINGS_FILE" ] && cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    python3 -c "
import json, os

settings_file = '$SETTINGS_FILE'
plugin_key = '${PLUGIN_NAME}@local-plugins'

if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        s = json.load(f)
else:
    s = {}

ep = s.setdefault('enabledPlugins', {})
ep[plugin_key] = True
with open(settings_file, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
print('Plugin enabled in settings.json')
"
    info "Plugin enabled in settings.json"
else
    warn "python3 not found. Manually add '\"${PLUGIN_NAME}@local-plugins\": true' to $SETTINGS_FILE"
fi

# Step 7: Verify
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Plugin files:"
ls -la "$PLUGIN_DIR/" 2>/dev/null
echo ""
echo "Status in settings.json:"
grep -o "\"${PLUGIN_NAME}[^\"]*\"[^,}]*" "$SETTINGS_FILE" 2>/dev/null || echo "(check manually)"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load the plugin"
echo "  2. Use: /prod-ready         (full audit)"
echo "  3. Use: /prod-ready security (security only)"
echo "  4. Use: /prod-ready deps     (dependency audit)"
echo "  5. Use: /prod-ready build    (build verification)"
echo "  6. Use: /prod-ready cicd     (CI/CD validation)"
echo ""
