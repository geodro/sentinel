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

# ── Shell wrappers + PATH setup ───────────────────────────────────────────────

SHELL_NAME="$(basename "${SHELL:-bash}")"
info "Detected shell: ${SHELL_NAME}"

# Helper: check if INSTALL_DIR is currently on PATH
_in_path() { echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; }

RELOAD_CMD=""

case "$SHELL_NAME" in
    fish)
        FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
        FISH_FUNC_DIR="$FISH_CONFIG_DIR/functions"
        FISH_CONFIG="$FISH_CONFIG_DIR/config.fish"
        mkdir -p "$FISH_FUNC_DIR"
        # Fish requires one function per file named after the function
        for fn in git npm composer curl wget tar unzip 7z 7za; do
            grep -A 999 "^function ${fn} " "$REPO_DIR/shell/sentinel.fish" \
                | awk '/^end$/{print; exit} {print}' \
                > "$FISH_FUNC_DIR/${fn}.fish"
        done
        ok "Fish functions written to ${FISH_FUNC_DIR}"
        # Add INSTALL_DIR to fish_user_paths if not already on PATH
        if ! _in_path; then
            if grep -q "fish_add_path.*${INSTALL_DIR}" "$FISH_CONFIG" 2>/dev/null; then
                warn "${INSTALL_DIR} PATH entry already in ${FISH_CONFIG} — skipping"
            else
                echo "" >> "$FISH_CONFIG"
                echo "# sentinel — ensure install dir is on PATH" >> "$FISH_CONFIG"
                echo "fish_add_path \"${INSTALL_DIR}\"" >> "$FISH_CONFIG"
                ok "Added ${INSTALL_DIR} to PATH via fish_add_path in ${FISH_CONFIG}"
            fi
            # Make PATH available for the remainder of this script
            export PATH="$INSTALL_DIR:$PATH"
        fi
        # Source wrappers explicitly in config.fish so they override any system
        # aliases (e.g. distro configs that define 'alias wget=wget -c').
        if grep -q 'sentinel.*override system aliases' "$FISH_CONFIG" 2>/dev/null; then
            warn "sentinel override block already in ${FISH_CONFIG} — skipping"
        else
            cat >> "$FISH_CONFIG" << 'EOF'

# sentinel — override system aliases so wrappers take effect
for __sentinel_fn in git npm composer curl wget tar unzip 7z 7za
    if test -f "$HOME/.config/fish/functions/$__sentinel_fn.fish"
        source "$HOME/.config/fish/functions/$__sentinel_fn.fish"
    end
end
set -e __sentinel_fn
EOF
            ok "Appended override block to ${FISH_CONFIG}"
        fi
        RELOAD_CMD="exec fish"
        ;;
    zsh)
        ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
        if ! _in_path; then
            if grep -q "PATH.*${INSTALL_DIR}" "$ZSHRC" 2>/dev/null; then
                warn "${INSTALL_DIR} PATH entry already in ${ZSHRC} — skipping"
            else
                echo "" >> "$ZSHRC"
                echo "# sentinel — ensure install dir is on PATH" >> "$ZSHRC"
                echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$ZSHRC"
                ok "Added ${INSTALL_DIR} to PATH in ${ZSHRC}"
            fi
            # Make PATH available for the remainder of this script
            export PATH="$INSTALL_DIR:$PATH"
        fi
        if grep -q 'sentinel.zsh' "$ZSHRC" 2>/dev/null; then
            warn "sentinel already sourced in ${ZSHRC} — skipping"
        else
            echo "" >> "$ZSHRC"
            echo "# sentinel shell wrappers" >> "$ZSHRC"
            echo "source \"${REPO_DIR}/shell/sentinel.zsh\"" >> "$ZSHRC"
            ok "Appended source line to ${ZSHRC}"
        fi
        RELOAD_CMD="source ${ZSHRC}"
        ;;
    bash)
        BASHRC="$HOME/.bashrc"
        if ! _in_path; then
            if grep -q "PATH.*${INSTALL_DIR}" "$BASHRC" 2>/dev/null; then
                warn "${INSTALL_DIR} PATH entry already in ${BASHRC} — skipping"
            else
                echo "" >> "$BASHRC"
                echo "# sentinel — ensure install dir is on PATH" >> "$BASHRC"
                echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$BASHRC"
                ok "Added ${INSTALL_DIR} to PATH in ${BASHRC}"
            fi
            # Make PATH available for the remainder of this script
            export PATH="$INSTALL_DIR:$PATH"
        fi
        if grep -q 'sentinel.bash' "$BASHRC" 2>/dev/null; then
            warn "sentinel already sourced in ${BASHRC} — skipping"
        else
            echo "" >> "$BASHRC"
            echo "# sentinel shell wrappers" >> "$BASHRC"
            echo "source \"${REPO_DIR}/shell/sentinel.bash\"" >> "$BASHRC"
            ok "Appended source line to ${BASHRC}"
        fi
        RELOAD_CMD="source ${BASHRC}"
        ;;
    *)
        warn "Unknown shell '${SHELL_NAME}' — manually source the appropriate file from shell/"
        if ! _in_path; then
            warn "Also add ${INSTALL_DIR} to your PATH"
            export PATH="$INSTALL_DIR:$PATH"
        fi
        ;;
esac

echo ""
ok "Done. Run 'sentinel --help' or see README.md for usage."
if [[ -n "$RELOAD_CMD" ]]; then
    ok "Reload your shell to apply changes: ${RELOAD_CMD}"
fi
