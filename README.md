# sentinel

Automatic ClamAV malware scanning and vulnerability auditing for `npm`, `composer`, and `git` operations. Wraps your shell commands so every install, clone, or pull is scanned transparently.

## What it does

| Command | ClamAV scan | Audit |
|---|---|---|
| `npm install` / `npm i` / `npm ci` / `npm update` | `node_modules/` | `npm audit` |
| `composer install` / `composer update` / `composer require` | `vendor/` | `composer audit` |
| `git clone <url>` | cloned directory | — |
| `git pull` / `git fetch` | current directory | — |

Infected files are quarantined (moved, not deleted). Audit warnings are non-fatal; malware detections block with a non-zero exit code.

---

## Prerequisites

### Linux

**ClamAV** (required for malware scanning):
```bash
# Debian / Ubuntu
sudo apt install clamav clamav-daemon
sudo freshclam

# Arch / CachyOS
sudo pacman -S clamav
sudo freshclam

# Fedora / RHEL
sudo dnf install clamav clamd
sudo freshclam
```

**npm audit** — included with Node.js / npm (no extra install needed).

**composer audit** — included with Composer 2.4+:
```bash
composer --version   # must be >= 2.4
```

### macOS

**ClamAV** via Homebrew:
```bash
brew install clamav
# Copy the sample config and update signatures
cp /opt/homebrew/etc/clamav/freshclam.conf.sample /opt/homebrew/etc/clamav/freshclam.conf
sed -i '' 's/^Example$//' /opt/homebrew/etc/clamav/freshclam.conf
freshclam
```

**npm** — install via [Node.js](https://nodejs.org) or `brew install node`.

**composer** — install via `brew install composer` (must be >= 2.4 for `composer audit`).

---

## Installation

```bash
git clone https://github.com/youruser/sentinel.git
cd sentinel
bash install.sh
```

The installer:
1. Copies `sentinel` to `~/.local/bin/` (configurable via `SENTINEL_INSTALL_DIR`)
2. Detects your shell and installs the appropriate wrappers automatically

### Manual shell setup

If you prefer to set up wrappers yourself:

**Fish** — copy each function into `~/.config/fish/functions/`:
```bash
# The file must be named after the function
cp shell/sentinel.fish ~/.config/fish/functions/  # then split manually, or:
# Run the installer — it handles splitting for you
```

**Zsh** — add to `~/.zshrc`:
```zsh
source /path/to/sentinel/shell/sentinel.zsh
```

**Bash** — add to `~/.bashrc`:
```bash
source /path/to/sentinel/shell/sentinel.bash
```

---

## Usage

Once installed the wrappers are transparent — just use your tools normally:

```bash
npm install
npm i express
composer install
composer require guzzlehttp/guzzle
git clone https://github.com/example/repo.git
git pull
```

You can also call sentinel directly:

```bash
sentinel npm install
sentinel composer install
sentinel git clone https://github.com/example/repo.git
```

---

## Configuration

All options are set via environment variables:

| Variable | Default | Description |
|---|---|---|
| `SENTINEL_QUARANTINE` | `/tmp/sentinel-quarantine` | Directory to move infected files into |
| `SENTINEL_CLAM_OPTS` | `--infected --suppress-ok-results` | Extra flags passed to `clamscan` |
| `SENTINEL_SKIP_CLAM` | `0` | Set to `1` to skip ClamAV scan |
| `SENTINEL_SKIP_AUDIT` | `0` | Set to `1` to skip npm/composer audit |

### Examples

```bash
# Skip ClamAV for a one-off install (e.g. known-safe internal package)
SENTINEL_SKIP_CLAM=1 npm install

# Use a custom quarantine location
SENTINEL_QUARANTINE=/var/quarantine git clone https://github.com/example/repo.git

# Skip audit warnings
SENTINEL_SKIP_AUDIT=1 composer install
```

---

## Keeping signatures up to date

ClamAV signatures must be updated regularly to detect new threats:

```bash
# Linux (run as root or via cron)
sudo freshclam

# macOS
freshclam
```

Recommended: set up a daily cron job:
```bash
# /etc/cron.daily/freshclam  (Linux)
#!/bin/sh
freshclam --quiet
```

---

## Uninstall

```bash
rm ~/.local/bin/sentinel

# Fish
rm ~/.config/fish/functions/git.fish
rm ~/.config/fish/functions/npm.fish
rm ~/.config/fish/functions/composer.fish

# Zsh — remove the source line from ~/.zshrc
# Bash — remove the source line from ~/.bashrc
```
