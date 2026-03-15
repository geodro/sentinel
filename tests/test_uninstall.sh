#!/usr/bin/env bash
set -euo pipefail

UNINSTALL_SH="/home/george/Projects/sentinel/uninstall.sh"
PASS=0; FAIL=0

ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $1 — $2"; FAIL=$((FAIL+1)); }

# Create a self-contained test environment
make_env() {
    local shell="$1"
    local dir; dir=$(mktemp -d)
    mkdir -p "$dir/bin" "$dir/home/.local/bin" "$dir/home/.local/share/sentinel/shell"
    mkdir -p "$dir/home/.config/fish/functions"

    # Place a fake sentinel binary
    touch "$dir/home/.local/bin/sentinel"
    touch "$dir/home/.local/share/sentinel/shell/sentinel.bash"
    touch "$dir/home/.local/share/sentinel/shell/sentinel.zsh"

    # Fish function files
    for fn in git npm composer curl wget tar unzip 7z 7za; do
        touch "$dir/home/.config/fish/functions/${fn}.fish"
    done

    # Fish config with sentinel block
    cat > "$dir/home/.config/fish/config.fish" << 'FISHEOF'
# some existing config
set -x FOO bar

# sentinel — ensure install dir is on PATH
fish_add_path "/home/test/.local/bin"

# sentinel — override system aliases so wrappers take effect
for __sentinel_fn in git npm composer curl wget tar unzip 7z 7za
    if test -f "$HOME/.config/fish/functions/$__sentinel_fn.fish"
        source "$HOME/.config/fish/functions/$__sentinel_fn.fish"
    end
end
set -e __sentinel_fn

# more existing config
set -x BAR baz
FISHEOF

    # Zsh config
    cat > "$dir/home/.zshrc" << 'ZSHEOF'
# existing zsh config
export FOO=bar

# sentinel — ensure install dir is on PATH
export PATH="/home/test/.local/bin:$PATH"

# sentinel shell wrappers
source "/home/test/sentinel/shell/sentinel.zsh"

# more existing config
export BAR=baz
ZSHEOF

    # Bash config
    cat > "$dir/home/.bashrc" << 'BASHEOF'
# existing bash config
export FOO=bar

# sentinel — ensure install dir is on PATH
export PATH="/home/test/.local/bin:$PATH"

# sentinel shell wrappers
source "/home/test/sentinel/shell/sentinel.bash"

# more existing config
export BAR=baz
BASHEOF

    echo "$dir"
}

run_uninstall() {
    local dir="$1" shell="$2" answer="$3"
    local out
    out=$(
        HOME="$dir/home" \
        SHELL="/bin/$shell" \
        SENTINEL_INSTALL_DIR="$dir/home/.local/bin" \
        SENTINEL_SHARE_DIR="$dir/home/.local/share/sentinel" \
        bash "$UNINSTALL_SH" <<< "$answer" 2>&1
    ) || true
    echo "$out"
}

# ── binary and share dir removal ─────────────────────────────────────────────

echo ""
echo "=== binary and share dir ==="
echo ""

echo "--- 1: sentinel binary is removed ---"
E=$(make_env bash)
run_uninstall "$E" bash "y" > /dev/null
if [[ ! -f "$E/home/.local/bin/sentinel" ]]; then
    ok "binary removed"
else
    fail "binary removed" "file still exists"
fi
rm -rf "$E"

echo ""
echo "--- 2: share dir is removed ---"
E=$(make_env bash)
run_uninstall "$E" bash "y" > /dev/null
if [[ ! -d "$E/home/.local/share/sentinel" ]]; then
    ok "share dir removed"
else
    fail "share dir removed" "dir still exists"
fi
rm -rf "$E"

echo ""
echo "--- 3: answering n aborts ---"
E=$(make_env bash)
run_uninstall "$E" bash "n" > /dev/null
if [[ -f "$E/home/.local/bin/sentinel" ]]; then
    ok "abort leaves binary intact"
else
    fail "abort leaves binary intact" "binary was removed"
fi
rm -rf "$E"

# ── bash cleanup ─────────────────────────────────────────────────────────────

echo ""
echo "=== bash shell cleanup ==="
echo ""

echo "--- 4: sentinel source line removed from .bashrc ---"
E=$(make_env bash)
run_uninstall "$E" bash "y" > /dev/null
if ! grep -q 'sentinel\.bash' "$E/home/.bashrc"; then
    ok "source line removed"
else
    fail "source line removed" "still present"
fi
rm -rf "$E"

echo ""
echo "--- 5: sentinel PATH line removed from .bashrc ---"
E=$(make_env bash)
run_uninstall "$E" bash "y" > /dev/null
if ! grep -q '# sentinel' "$E/home/.bashrc"; then
    ok "sentinel comments removed"
else
    fail "sentinel comments removed" "still present"
fi
rm -rf "$E"

echo ""
echo "--- 6: non-sentinel lines preserved in .bashrc ---"
E=$(make_env bash)
run_uninstall "$E" bash "y" > /dev/null
if grep -q 'export FOO=bar' "$E/home/.bashrc" && grep -q 'export BAR=baz' "$E/home/.bashrc"; then
    ok "existing config preserved"
else
    fail "existing config preserved" "lost non-sentinel lines"
fi
rm -rf "$E"

# ── zsh cleanup ──────────────────────────────────────────────────────────────

echo ""
echo "=== zsh shell cleanup ==="
echo ""

echo "--- 7: sentinel source line removed from .zshrc ---"
E=$(make_env zsh)
run_uninstall "$E" zsh "y" > /dev/null
if ! grep -q 'sentinel\.zsh' "$E/home/.zshrc"; then
    ok "source line removed"
else
    fail "source line removed" "still present"
fi
rm -rf "$E"

echo ""
echo "--- 8: non-sentinel lines preserved in .zshrc ---"
E=$(make_env zsh)
run_uninstall "$E" zsh "y" > /dev/null
if grep -q 'export FOO=bar' "$E/home/.zshrc" && grep -q 'export BAR=baz' "$E/home/.zshrc"; then
    ok "existing config preserved"
else
    fail "existing config preserved" "lost non-sentinel lines"
fi
rm -rf "$E"

# ── fish cleanup ─────────────────────────────────────────────────────────────

echo ""
echo "=== fish shell cleanup ==="
echo ""

echo "--- 9: fish function files removed ---"
E=$(make_env fish)
run_uninstall "$E" fish "y" > /dev/null
local_missing=0
for fn in git npm composer curl wget tar unzip 7z 7za; do
    [[ -f "$E/home/.config/fish/functions/${fn}.fish" ]] && local_missing=1
done
if [[ $local_missing -eq 0 ]]; then
    ok "fish function files removed"
else
    fail "fish function files removed" "some still exist"
fi
rm -rf "$E"

echo ""
echo "--- 10: sentinel block removed from config.fish ---"
E=$(make_env fish)
run_uninstall "$E" fish "y" > /dev/null
if ! grep -q 'sentinel' "$E/home/.config/fish/config.fish"; then
    ok "sentinel block removed from config.fish"
else
    fail "sentinel block removed from config.fish" "sentinel lines still present: $(grep 'sentinel' "$E/home/.config/fish/config.fish")"
fi
rm -rf "$E"

echo ""
echo "--- 11: non-sentinel lines preserved in config.fish ---"
E=$(make_env fish)
run_uninstall "$E" fish "y" > /dev/null
if grep -q 'set -x FOO bar' "$E/home/.config/fish/config.fish" && \
   grep -q 'set -x BAR baz' "$E/home/.config/fish/config.fish"; then
    ok "existing fish config preserved"
else
    fail "existing fish config preserved" "lost non-sentinel lines"
fi
rm -rf "$E"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
