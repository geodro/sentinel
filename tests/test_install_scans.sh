#!/usr/bin/env bash
# tests/test_install_scans.sh
# Integration tests for post-install scanning: composer scripts, composer project
# files (vendor:publish etc.), and npm project files (postinstall hooks).

set -uo pipefail

SENTINEL_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sentinel"
PASS=0
FAIL=0

# ── helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "  PASS $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $1 — $2"; FAIL=$((FAIL + 1)); }

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$label"
    else
        fail "$label" "expected to contain: '$needle'"
        echo "       got: $haystack"
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$label"
    else
        fail "$label" "must NOT contain: '$needle'"
    fi
}

assert_exit() {
    local label="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then ok "$label"; else fail "$label" "exit=$got want=$want"; fi
}

# ── fixture helpers ───────────────────────────────────────────────────────────

# Create a temp environment with fake composer and clamscan.
# Prints the env dir path.
make_env() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/bin" "$dir/project/vendor/composer" "$dir/project/vendor/bin" "$dir/project/node_modules"

    # symlink system utilities into the fake bin so isolated PATH works:
    #   bash   — needed by #!/usr/bin/env bash in sentinel and fake scripts
    #   mkdir  — needed by run_clamscan (quarantine dir creation)
    #   mktemp — needed by INSTALL_TIMESTAMP snapshot
    #   find   — needed by scan_published_assets
    #   rm     — needed to clean up INSTALL_TIMESTAMP after scans
    #   sleep  — used in fake composer scripts to ensure file mtime > timestamp
    #   touch  — used in fake composer scripts to create published asset files
    for cmd in bash mkdir mktemp find rm sleep touch; do
        local p; p="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -sf "$p" "$dir/bin/$cmd" || true
    done

    # fake composer and npm: always succeed regardless of subcommand
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/composer"
    chmod +x "$dir/bin/composer"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/npm"
    chmod +x "$dir/bin/npm"

    # fake clamscan: append args to log, always report clean
    cat > "$dir/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "CLAMSCAN $*" >> "$CLAMSCAN_LOG"
exit 0
EOF
    chmod +x "$dir/bin/clamscan"

    # link system jq (tests that need jq absent will remove this)
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "$dir/bin/jq"
    fi

    echo "$dir"
}

write_composer_json() {
    local dir="$1" content="$2"
    printf '%s\n' "$content" > "$dir/project/composer.json"
}

write_installed_json() {
    local dir="$1" content="$2"
    printf '%s\n' "$content" > "$dir/project/vendor/composer/installed.json"
}

# Run sentinel composer install in the fixture project dir.
# Sets SENTINEL_OUTPUT; returns sentinel's exit code.
SENTINEL_OUTPUT=""
run_sentinel() {
    local env_dir="$1"
    local extra_env="${2:-}"
    local log="$env_dir/clamscan.log"
    > "$log"

    local exit_code=0
    SENTINEL_OUTPUT=$(
        cd "$env_dir/project"
        export CLAMSCAN_LOG="$log"
        # Isolated PATH: only fake bin, so jq absence is detectable
        export PATH="$env_dir/bin"
        [[ -n "$extra_env" ]] && eval "export $extra_env"
        "$SENTINEL_BIN" composer install 2>&1
    ) || exit_code=$?
    return $exit_code
}

scan_log() { cat "$1/clamscan.log" 2>/dev/null || true; }

SENTINEL_NPM_OUTPUT=""
run_sentinel_npm() {
    local env_dir="$1"
    local extra_env="${2:-}"
    local log="$env_dir/clamscan.log"
    > "$log"

    local exit_code=0
    SENTINEL_NPM_OUTPUT=$(
        cd "$env_dir/project"
        export CLAMSCAN_LOG="$log"
        export PATH="$env_dir/bin"
        [[ -n "$extra_env" ]] && eval "export $extra_env"
        "$SENTINEL_BIN" npm install 2>&1
    ) || exit_code=$?
    return $exit_code
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== scan_composer_scripts ==="
echo ""

# 1. File-path entry in composer.json is scanned
echo "--- 1: file-path script in composer.json ---"
E=$(make_env)
mkdir -p "$E/project/scripts"
touch "$E/project/scripts/post-install.sh"
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./scripts/post-install.sh --arg"] }
}'
run_sentinel "$E" || true
assert_contains "file-path script scanned" "$(scan_log "$E")" "post-install.sh"
rm -rf "$E"

# 2. PHP callable (Class::method) is NOT passed to clamscan
echo ""
echo "--- 2: PHP callable is not scanned ---"
E=$(make_env)
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["Illuminate\\\\Foundation\\\\ComposerScripts::postUpdate"] }
}'
run_sentinel "$E" || true
assert_not_contains "PHP callable not scanned" "$(scan_log "$E")" "ComposerScripts"
rm -rf "$E"

# 3. @-alias is NOT passed to clamscan
echo ""
echo "--- 3: @-alias is not scanned ---"
E=$(make_env)
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["@php artisan package:discover"] }
}'
run_sentinel "$E" || true
assert_not_contains "@-alias not scanned" "$(scan_log "$E")" "artisan"
rm -rf "$E"

# 4. Non-existent file path is not scanned (no crash)
echo ""
echo "--- 4: non-existent file path not scanned ---"
E=$(make_env)
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./does-not-exist.sh"] }
}'
exit_code=0
run_sentinel "$E" || exit_code=$?
assert_exit         "exits cleanly"              "$exit_code" "0"
assert_not_contains "missing file not scanned"   "$(scan_log "$E")" "does-not-exist.sh"
rm -rf "$E"

# 5. File-path from vendor/composer/installed.json is scanned
echo ""
echo "--- 5: file-path from installed.json ---"
E=$(make_env)
write_composer_json "$E" '{"require": {}}'
mkdir -p "$E/project/bin"
touch "$E/project/bin/pkg-hook.sh"
write_installed_json "$E" '{
  "packages": [{
    "name": "vendor/pkg",
    "scripts": { "post-install-cmd": ["./bin/pkg-hook.sh"] }
  }]
}'
run_sentinel "$E" || true
assert_contains "installed.json script scanned" "$(scan_log "$E")" "pkg-hook.sh"
rm -rf "$E"

# 6. Same file appearing in both sources is scanned only once
echo ""
echo "--- 6: deduplication ---"
E=$(make_env)
mkdir -p "$E/project/scripts"
touch "$E/project/scripts/shared.sh"
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./scripts/shared.sh"] }
}'
write_installed_json "$E" '{
  "packages": [{
    "name": "vendor/pkg",
    "scripts": { "post-install-cmd": ["./scripts/shared.sh"] }
  }]
}'
run_sentinel "$E" || true
# grep -c exits 1 on 0 matches; suppress that with '; true' to avoid double-print
count=$(grep -c "shared.sh" "$E/clamscan.log" 2>/dev/null; true)
if [[ "$count" -eq 1 ]]; then
    ok "deduplicated: scanned exactly once"
else
    fail "deduplicated" "scanned $count times, want 1"
fi
rm -rf "$E"

# 7. jq absent: emits warning, does not fail sentinel
echo ""
echo "--- 7: jq absent → warn, no failure ---"
E=$(make_env)
rm -f "$E/bin/jq"
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./script.sh"] }
}'
exit_code=0
run_sentinel "$E" || exit_code=$?
assert_contains "warns when jq absent" "$SENTINEL_OUTPUT" "jq not found"
assert_exit     "no failure when jq absent" "$exit_code" "0"
rm -rf "$E"

# 8. SENTINEL_SKIP_CLAM=1 suppresses script scan
echo ""
echo "--- 8: SENTINEL_SKIP_CLAM=1 suppresses script scan ---"
E=$(make_env)
mkdir -p "$E/project/scripts"
touch "$E/project/scripts/post-install.sh"
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./scripts/post-install.sh"] }
}'
run_sentinel "$E" "SENTINEL_SKIP_CLAM=1" || true
assert_not_contains "skip clam suppresses scan" "$(scan_log "$E")" "post-install.sh"
rm -rf "$E"

# 9. clamscan failure on a script file propagates as non-zero exit
echo ""
echo "--- 9: infected script file causes non-zero exit ---"
E=$(make_env)
mkdir -p "$E/project/scripts"
touch "$E/project/scripts/malicious.sh"
# Override clamscan to return exit 1 (threat found) only for this file
cat > "$E/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "CLAMSCAN $*" >> "$CLAMSCAN_LOG"
if [[ "$*" == *"malicious.sh"* ]]; then exit 1; fi
exit 0
EOF
chmod +x "$E/bin/clamscan"
write_composer_json "$E" '{
  "scripts": { "post-install-cmd": ["./scripts/malicious.sh"] }
}'
exit_code=0
run_sentinel "$E" || exit_code=$?
assert_exit "infected script causes non-zero exit" "$exit_code" "2"
rm -rf "$E"

# ── scan_composer_project_files tests ────────────────────────────────────────

echo ""
echo "=== scan_composer_project_files ==="
echo ""

# 10. No new project files written → no extra scan
echo "--- 10: no new project files → silently skipped ---"
E=$(make_env)
write_composer_json "$E" '{"require": {}}'
exit_code=0
run_sentinel "$E" || exit_code=$?
assert_exit     "no new files → exit 0"              "$exit_code" "0"
assert_not_contains "no new files → no project scan" "$(scan_log "$E")" "project tree"
rm -rf "$E"

# 11. File written to public/ by a post-install script is scanned
echo ""
echo "--- 11: file written to public/ during install is scanned ---"
E=$(make_env)
cat > "$E/bin/composer" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./public/js/vendor
touch ./public/js/vendor/app.js
exit 0
EOF
write_composer_json "$E" '{"require": {}}'
run_sentinel "$E" || true
assert_contains "public/ file scanned" "$(scan_log "$E")" "app.js"
rm -rf "$E"

# 12. File written to config/ by vendor:publish is also scanned
echo ""
echo "--- 12: file written to config/ during install is scanned ---"
E=$(make_env)
cat > "$E/bin/composer" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./config
touch ./config/package.php
exit 0
EOF
write_composer_json "$E" '{"require": {}}'
run_sentinel "$E" || true
assert_contains "config/ file scanned" "$(scan_log "$E")" "package.php"
rm -rf "$E"

# 13. Pre-existing files (older than timestamp) are NOT re-scanned
echo ""
echo "--- 13: pre-existing project files not re-scanned ---"
E=$(make_env)
mkdir -p "$E/project/config"
touch "$E/project/config/existing.php"
sleep 0.1
write_composer_json "$E" '{"require": {}}'
run_sentinel "$E" || true
assert_not_contains "old project file not re-scanned" "$(scan_log "$E")" "existing.php"
rm -rf "$E"

# 14. File inside vendor/ is NOT double-scanned by the project scan
echo ""
echo "--- 14: vendor/ files excluded from project scan ---"
E=$(make_env)
cat > "$E/bin/composer" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
touch ./vendor/injected.php
exit 0
EOF
write_composer_json "$E" '{"require": {}}'
run_sentinel "$E" || true
log=$(scan_log "$E")
vendor_in_project_scan=$(echo "$log" | grep "injected.php" | grep -v "\-r ./vendor" || true)
if [[ -z "$vendor_in_project_scan" ]]; then
    ok "vendor/ file not double-scanned by project scan"
else
    fail "vendor/ file not double-scanned by project scan" "extra scan: $vendor_in_project_scan"
fi
rm -rf "$E"

# 15. Infected project file causes non-zero exit
echo ""
echo "--- 15: infected project file causes non-zero exit ---"
E=$(make_env)
cat > "$E/bin/composer" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./config
touch ./config/malware.php
exit 0
EOF
cat > "$E/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "CLAMSCAN $*" >> "$CLAMSCAN_LOG"
if [[ "$*" == *"malware.php"* ]]; then exit 1; fi
exit 0
EOF
chmod +x "$E/bin/clamscan"
write_composer_json "$E" '{"require": {}}'
exit_code=0
run_sentinel "$E" || exit_code=$?
assert_exit "infected project file → exit 2" "$exit_code" "2"
rm -rf "$E"

# 16. SENTINEL_SKIP_CLAM=1 skips project files scan
echo ""
echo "--- 16: SENTINEL_SKIP_CLAM=1 skips project files scan ---"
E=$(make_env)
cat > "$E/bin/composer" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./config
touch ./config/skipped.php
exit 0
EOF
write_composer_json "$E" '{"require": {}}'
run_sentinel "$E" "SENTINEL_SKIP_CLAM=1" || true
assert_not_contains "skip clam skips project scan" "$(scan_log "$E")" "skipped.php"
rm -rf "$E"

# ── scan_npm_project_files tests ──────────────────────────────────────────────

echo ""
echo "=== scan_npm_project_files ==="
echo ""

# 17. No new project files written → project scan skipped silently
echo "--- 17: no new project files → silently skipped ---"
E=$(make_env)
exit_code=0
run_sentinel_npm "$E" || exit_code=$?
assert_exit     "no new files → exit 0"    "$exit_code" "0"
assert_not_contains "no new files → no project scan" "$(scan_log "$E")" "project tree"
rm -rf "$E"

# 18. File written to dist/ by postinstall is scanned
echo ""
echo "--- 18: file written to dist/ during install is scanned ---"
E=$(make_env)
cat > "$E/bin/npm" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./dist
touch ./dist/bundle.js
exit 0
EOF
run_sentinel_npm "$E" || true
assert_contains "dist/ file scanned" "$(scan_log "$E")" "bundle.js"
rm -rf "$E"

# 19. File inside node_modules/ is NOT included in project files scan (already covered)
echo ""
echo "--- 19: node_modules/ files excluded from project scan ---"
E=$(make_env)
cat > "$E/bin/npm" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
touch ./node_modules/injected.js
exit 0
EOF
run_sentinel_npm "$E" || true
log=$(scan_log "$E")
# node_modules/ is scanned by run_clamscan (first CLAMSCAN call covers it)
# the project-files scan must NOT add a second clamscan call for that file
injected_in_project_scan=$(echo "$log" | grep "injected.js" | grep -v "\-r ./node_modules" || true)
if [[ -z "$injected_in_project_scan" ]]; then
    ok "node_modules file not double-scanned by project scan"
else
    fail "node_modules file not double-scanned by project scan" "found extra scan: $injected_in_project_scan"
fi
rm -rf "$E"

# 20. File inside .git/ is NOT scanned
echo ""
echo "--- 20: .git/ files excluded from project scan ---"
E=$(make_env)
mkdir -p "$E/project/.git"
cat > "$E/bin/npm" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
touch ./.git/injected
exit 0
EOF
run_sentinel_npm "$E" || true
assert_not_contains ".git/ excluded" "$(scan_log "$E")" ".git/injected"
rm -rf "$E"

# 21. Infected file in project tree causes non-zero exit
echo ""
echo "--- 21: infected project file causes non-zero exit ---"
E=$(make_env)
cat > "$E/bin/npm" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./dist
touch ./dist/malware.js
exit 0
EOF
cat > "$E/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "CLAMSCAN $*" >> "$CLAMSCAN_LOG"
if [[ "$*" == *"malware.js"* ]]; then exit 1; fi
exit 0
EOF
chmod +x "$E/bin/clamscan"
exit_code=0
run_sentinel_npm "$E" || exit_code=$?
assert_exit "infected project file → exit 2" "$exit_code" "2"
rm -rf "$E"

# 22. SENTINEL_SKIP_CLAM=1 skips project files scan
echo ""
echo "--- 22: SENTINEL_SKIP_CLAM=1 skips project files scan ---"
E=$(make_env)
cat > "$E/bin/npm" <<'EOF'
#!/usr/bin/env bash
sleep 0.1
mkdir -p ./dist
touch ./dist/skipped.js
exit 0
EOF
run_sentinel_npm "$E" "SENTINEL_SKIP_CLAM=1" || true
assert_not_contains "skip clam skips project scan" "$(scan_log "$E")" "skipped.js"
rm -rf "$E"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""
[[ $FAIL -eq 0 ]]
