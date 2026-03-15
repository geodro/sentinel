#!/usr/bin/env bash
# install.sh — Install sentinel and shell wrappers

set -euo pipefail

INSTALL_DIR="${SENTINEL_INSTALL_DIR:-$HOME/.local/bin}"
SHARE_DIR="${SENTINEL_SHARE_DIR:-$HOME/.local/share/sentinel}"
REPO_URL="https://raw.githubusercontent.com/geodro/sentinel/main"

# When run via the one-liner (bash -c "$(curl ...)"), BASH_SOURCE[0] is not a
# real file path, so REPO_DIR resolves to the current directory.  Detect this
# and download the necessary files to SHARE_DIR instead.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${BOLD}==> $*${RESET}"; }
ok()    { echo -e "${GREEN}    $*${RESET}"; }
warn()  { echo -e "${YELLOW}    WARNING: $*${RESET}"; }
error() { echo -e "${RED}    ERROR: $*${RESET}"; }

# Detect the system package manager.
_pkg_manager() {
    if [[ "$(uname -s)" == Darwin ]]; then
        echo "brew"
        return
    fi
    if [[ -f /etc/os-release ]]; then
        local id id_like
        id=$(. /etc/os-release && echo "${ID:-}")
        id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
        case "$id $id_like" in
            *debian*|*ubuntu*) echo "apt"    ; return ;;
            *arch*)            echo "pacman" ; return ;;
            *fedora*|*rhel*|*centos*) echo "dnf" ; return ;;
        esac
    fi
    echo "unknown"
}

# Return the install command for a given binary + package manager.
_install_cmd() {
    local cmd="$1" mgr="$2"
    case "$mgr:$cmd" in
        brew:clamscan)   echo "brew install clamav && freshclam" ;;
        brew:jq)         echo "brew install jq" ;;
        apt:clamscan)    echo "sudo apt install -y clamav clamav-daemon && sudo freshclam" ;;
        apt:jq)          echo "sudo apt install -y jq" ;;
        pacman:clamscan) echo "sudo pacman -S --noconfirm clamav && sudo freshclam" ;;
        pacman:jq)       echo "sudo pacman -S --noconfirm jq" ;;
        dnf:clamscan)    echo "sudo dnf install -y clamav clamd && sudo freshclam" ;;
        dnf:jq)          echo "sudo dnf install -y jq" ;;
        *)               echo "" ;;
    esac
}

# Check a prerequisite binary; prompt to install if missing.
# required=1 → abort on decline; required=0 → warn and continue.
_check_prereq() {
    local cmd="$1" label="$2" required="${3:-1}"

    if command -v "$cmd" &>/dev/null; then
        ok "${label} found"
        return 0
    fi

    local install_cmd
    install_cmd="$(_install_cmd "$cmd" "$PKG_MGR")"

    echo ""
    warn "${label} is not installed"
    if [[ -n "$install_cmd" ]]; then
        echo -e "    Suggested command: ${BOLD}${install_cmd}${RESET}"
    else
        echo "    Install ${label} for your OS, then re-run this installer."
    fi
    echo ""

    local prompt ans
    if [[ "$required" -eq 1 ]]; then
        prompt="    Install now? [Y/n]: "
    else
        prompt="    Install now? [Y/n] (optional — skip to continue without it): "
    fi
    printf "%s" "$prompt"
    read -r ans </dev/tty || ans=""

    case "${ans,,}" in
        ""|y|yes)
            if [[ -n "$install_cmd" ]]; then
                echo ""
                eval "$install_cmd" || {
                    error "Installation of ${label} failed. Please install it manually and re-run."
                    [[ "$required" -eq 1 ]] && exit 1
                    return 0
                }
            else
                warn "No install command known for this system. Install ${label} manually."
                [[ "$required" -eq 1 ]] && exit 1
            fi
            ;;
        *)
            if [[ "$required" -eq 1 ]]; then
                echo "Aborting — ${label} is required for sentinel to function."
                exit 1
            else
                warn "Skipping ${label} — composer script scanning will be unavailable."
            fi
            ;;
    esac
    echo ""
}

# ── Remote download (one-liner install) ───────────────────────────────────────

# If the sentinel binary isn't next to this script we're running remotely.
# Download all required files to SHARE_DIR so they persist after install.
if [[ ! -f "$REPO_DIR/sentinel" ]] || [[ ! -d "$REPO_DIR/shell" ]]; then
    info "Downloading sentinel..."
    mkdir -p "$SHARE_DIR/shell"
    _download() {
        curl -fsSL "${REPO_URL}/$1" -o "${SHARE_DIR}/$1" || {
            error "Failed to download $1"
            exit 1
        }
    }
    _download sentinel
    _download shell/sentinel.bash
    _download shell/sentinel.zsh
    _download shell/sentinel.fish
    chmod +x "$SHARE_DIR/sentinel"
    ok "Downloaded to ${SHARE_DIR}"
    REPO_DIR="$SHARE_DIR"
fi

# ── Prerequisites ──────────────────────────────────────────────────────────────

info "Checking prerequisites..."
PKG_MGR="$(_pkg_manager)"
_check_prereq clamscan "ClamAV" 1
_check_prereq jq       "jq"     0

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

# ── ClamAV signature update ───────────────────────────────────────────────────

echo ""
printf "    Update ClamAV signatures now? (recommended) [Y/n]: "
read -r _freshclam_ans </dev/tty || _freshclam_ans=""
case "${_freshclam_ans,,}" in
    ""|y|yes)
        if [[ "$(uname -s)" == Darwin ]]; then
            freshclam
        else
            sudo freshclam
        fi
        ;;
    *)
        warn "Skipping signature update — run 'sudo freshclam' to update manually."
        ;;
esac
