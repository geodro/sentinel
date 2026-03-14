#!/usr/bin/env bash
# install.sh — Install sentinel and shell wrappers

set -euo pipefail

INSTALL_DIR="${SENTINEL_INSTALL_DIR:-$HOME/.local/bin}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}==> $*${RESET}"; }
ok()   { echo -e "${GREEN}    $*${RESET}"; }
warn() { echo -e "${YELLOW}    WARNING: $*${RESET}"; }

# ── Install binary ────────────────────────────────────────────────────────────

info "Installing sentinel to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/sentinel" "$INSTALL_DIR/sentinel"
chmod +x "$INSTALL_DIR/sentinel"
ok "sentinel installed to ${INSTALL_DIR}/sentinel"

# Check it's on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    warn "${INSTALL_DIR} is not in your PATH — add it to your shell config"
fi

# ── Shell wrappers ────────────────────────────────────────────────────────────

SHELL_NAME="$(basename "${SHELL:-bash}")"
info "Detected shell: ${SHELL_NAME}"

case "$SHELL_NAME" in
    fish)
        FISH_FUNC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
        mkdir -p "$FISH_FUNC_DIR"
        # Fish requires one function per file named after the function
        for fn in git npm composer; do
            grep -A 999 "^function ${fn} " "$REPO_DIR/shell/sentinel.fish" \
                | awk '/^end$/{print; exit} {print}' \
                > "$FISH_FUNC_DIR/${fn}.fish"
        done
        ok "Fish functions written to ${FISH_FUNC_DIR}"
        ok "Reload with: exec fish"
        ;;
    zsh)
        ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
        if grep -q 'sentinel.zsh' "$ZSHRC" 2>/dev/null; then
            warn "sentinel already sourced in ${ZSHRC} — skipping"
        else
            echo "" >> "$ZSHRC"
            echo "# sentinel shell wrappers" >> "$ZSHRC"
            echo "source \"${REPO_DIR}/shell/sentinel.zsh\"" >> "$ZSHRC"
            ok "Appended source line to ${ZSHRC}"
            ok "Reload with: source ${ZSHRC}"
        fi
        ;;
    bash)
        BASHRC="$HOME/.bashrc"
        if grep -q 'sentinel.bash' "$BASHRC" 2>/dev/null; then
            warn "sentinel already sourced in ${BASHRC} — skipping"
        else
            echo "" >> "$BASHRC"
            echo "# sentinel shell wrappers" >> "$BASHRC"
            echo "source \"${REPO_DIR}/shell/sentinel.bash\"" >> "$BASHRC"
            ok "Appended source line to ${BASHRC}"
            ok "Reload with: source ${BASHRC}"
        fi
        ;;
    *)
        warn "Unknown shell '${SHELL_NAME}' — manually source the appropriate file from shell/"
        ;;
esac

echo ""
ok "Done. Run 'sentinel --help' or see README.md for usage."
