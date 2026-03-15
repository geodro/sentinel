#!/usr/bin/env bash
# uninstall.sh — Remove sentinel and its shell wrappers

set -euo pipefail

INSTALL_DIR="${SENTINEL_INSTALL_DIR:-$HOME/.local/bin}"
SHARE_DIR="${SENTINEL_SHARE_DIR:-$HOME/.local/share/sentinel}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}==> $*${RESET}"; }
ok()   { echo -e "${GREEN}    $*${RESET}"; }
warn() { echo -e "${YELLOW}    WARNING: $*${RESET}"; }

echo ""
echo -e "${BOLD}This will remove sentinel and its shell wrappers.${RESET}"
echo ""
printf "    Continue? [y/N]: "
read -r _ans </dev/tty 2>/dev/null || read -r _ans 2>/dev/null || _ans=""
echo ""

case "$(echo "$_ans" | tr '[:upper:]' '[:lower:]')" in
    y|yes) ;;
    *)
        echo "    Aborted."
        exit 0
        ;;
esac

# Remove matching lines from a file using a temp file (portable, no sed -i issues).
_remove_lines() {
    local file="$1" pattern="$2"
    [[ -f "$file" ]] || return 0
    local tmp; tmp=$(mktemp)
    grep -v "$pattern" "$file" > "$tmp" || true
    mv "$tmp" "$file"
}

SHELL_NAME="$(basename "${SHELL:-bash}")"

# ── Shell wrappers ────────────────────────────────────────────────────────────

info "Removing shell wrappers..."

case "$SHELL_NAME" in
    fish)
        FISH_FUNC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
        FISH_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"

        for fn in git npm composer curl wget tar unzip 7z 7za; do
            rm -f "$FISH_FUNC_DIR/${fn}.fish"
        done
        ok "Removed Fish function files from ${FISH_FUNC_DIR}"

        if [[ -f "$FISH_CONFIG" ]]; then
            # Remove the multi-line sentinel override block.
            _tmp=$(mktemp)
            awk '
                /^# sentinel — override system aliases/ { skip=1 }
                /^set -e __sentinel_fn/                { if (skip) { skip=0; next } }
                !skip
            ' "$FISH_CONFIG" > "$_tmp"
            # Remove PATH and empty-block remnants.
            grep -v '# sentinel — ensure install dir is on PATH' "$_tmp" \
                | grep -v 'fish_add_path.*'"$INSTALL_DIR" > "$FISH_CONFIG" || true
            rm -f "$_tmp"
            ok "Cleaned ${FISH_CONFIG}"
        fi
        ;;
    zsh)
        ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
        _remove_lines "$ZSHRC" '# sentinel'
        _remove_lines "$ZSHRC" 'sentinel\.zsh'
        _remove_lines "$ZSHRC" "PATH.*${INSTALL_DIR}"
        ok "Cleaned ${ZSHRC}"
        ;;
    bash)
        BASHRC="$HOME/.bashrc"
        _remove_lines "$BASHRC" '# sentinel'
        _remove_lines "$BASHRC" 'sentinel\.bash'
        _remove_lines "$BASHRC" "PATH.*${INSTALL_DIR}"
        ok "Cleaned ${BASHRC}"
        ;;
    *)
        warn "Unknown shell '${SHELL_NAME}' — remove sentinel wrappers from your shell config manually."
        ;;
esac

# ── Binary and share directory ────────────────────────────────────────────────

info "Removing sentinel files..."

if [[ -f "$INSTALL_DIR/sentinel" ]]; then
    rm -f "$INSTALL_DIR/sentinel"
    ok "Removed ${INSTALL_DIR}/sentinel"
fi

if [[ -d "$SHARE_DIR" ]]; then
    rm -rf "$SHARE_DIR"
    ok "Removed ${SHARE_DIR}"
fi

echo ""
ok "sentinel uninstalled. Reload your shell to apply changes."
