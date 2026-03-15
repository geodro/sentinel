# sentinel

Automatic malware scanning and vulnerability auditing for package installs, git operations, downloads, and archive extraction. Sentinel wraps common shell commands so every operation that brings new code onto your machine is scanned transparently — no change to your workflow required.

## How it works

Shell wrappers intercept specific subcommands and route them through the `sentinel` binary, which runs the original command and then scans what was fetched. Non-intercepted subcommands (e.g. `git status`, `npm run build`, `tar cf ...`) pass straight through to the real binary with zero overhead.

ClamAV is used for malware detection, running with both signature matching and heuristic analysis (packed/obfuscated executables, phishing content, potentially unwanted programs). For npm and composer, a vulnerability audit is also run after every install.

Infected files are **moved** to a quarantine directory (not deleted). Malware detections exit with code `2`, failing the operation. Audit warnings are non-fatal.

## What gets scanned

| Command | Intercepts | ClamAV scan | Audit |
|---|---|---|---|
| `npm install` / `i` / `ci` / `update` / `up` | install operations only | `node_modules/` + project tree¹ | `npm audit` |
| `composer install` / `update` / `require` | install operations only | `vendor/` + script files² + project tree³ | `composer audit` |
| `git clone <url>` | clone only | cloned directory | — |
| `git pull` / `git fetch` | pull/fetch only | current directory | — |
| `curl -o file …` / `curl -O <url>` | file-writing invocations only | downloaded file | — |
| `wget <url>` | file-writing invocations only | downloaded file or directory | — |
| `tar xf …` / `tar -xzf …` / `tar --extract` | extract operations only | extraction directory | — |
| `unzip archive.zip` | all invocations | extraction directory | — |
| `7z x …` / `7za e …` | extract operations (`x`/`e`) only | extraction directory | — |

**¹ npm project tree** — after install, any file written outside `node_modules/` and `.git/` during the run (e.g. by a `postinstall` script dropping files into `dist/` or `public/`) is detected via timestamp comparison and scanned.

**² composer script files** — file-path entries in the `scripts` section of `composer.json` and `vendor/composer/installed.json` are scanned individually after install. PHP callables (`Vendor\Pkg::method`) and `@`-aliases are covered by the `vendor/` scan. Requires `jq`.

**³ composer project tree** — same timestamp approach as npm: any file written outside `vendor/` and `.git/` during the install run is scanned. This catches `vendor:publish` output (`config/`, `resources/views/vendor/`, `lang/`, `public/`, `database/migrations/`, etc.) regardless of which command produced it.

**curl/wget note:** invocations that stream to stdout (`curl` without `-o`/`-O`, `wget -O -`) pass through unwrapped — there is no file to scan.

**tar/7z note:** create and list operations pass through directly; only extract operations are intercepted.

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

**jq** (required for composer script scanning) — enables scanning of file-path entries in composer `scripts`:
```bash
# Debian / Ubuntu
sudo apt install jq

# Arch / CachyOS
sudo pacman -S jq

# Fedora / RHEL
sudo dnf install jq
```

### macOS

**ClamAV** via Homebrew:
```bash
brew install clamav
cp /opt/homebrew/etc/clamav/freshclam.conf.sample /opt/homebrew/etc/clamav/freshclam.conf
sed -i '' 's/^Example$//' /opt/homebrew/etc/clamav/freshclam.conf
freshclam
```

**npm** — install via [Node.js](https://nodejs.org) or `brew install node`.

**composer** — install via `brew install composer` (must be >= 2.4 for `composer audit`).

**jq** (required for composer script scanning) — `brew install jq`.

---

## Installation

### One-liner

```bash
# curl
bash -c "$(curl -fsSL https://raw.githubusercontent.com/geodro/sentinel/main/install.sh)"
```

```bash
# wget
bash -c "$(command wget -qO- https://raw.githubusercontent.com/geodro/sentinel/main/install.sh)"
```

> **Note:** `command wget` bypasses sentinel's shell wrapper. Without it, if sentinel is already installed, the wrapper intercepts the call and may fail if `~/.local/bin` is not yet on `PATH`.

### From a local clone

```bash
git clone https://github.com/geodro/sentinel.git
cd sentinel
bash install.sh
```

The installer:
1. Copies `sentinel` to `~/.local/bin/` (configurable via `SENTINEL_INSTALL_DIR`)
2. Detects your shell and installs the appropriate wrappers automatically
3. Adds `~/.local/bin` to `PATH` in your shell config if it isn't there already

### Manual shell setup

**Fish** — the installer splits `shell/sentinel.fish` into individual function files in `~/.config/fish/functions/`. To do it manually, extract each `function … end` block into its own file named after the function (e.g. `git.fish`).

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
curl -O https://example.com/tool.tar.gz
wget https://example.com/tool.tar.gz
tar xf tool.tar.gz
unzip archive.zip
7z x archive.7z
```

You can also call sentinel directly (useful in CI or scripts):

```bash
sentinel npm install
sentinel composer install
sentinel git clone https://github.com/example/repo.git
sentinel curl -O https://example.com/tool.tar.gz
sentinel wget https://example.com/tool.tar.gz
sentinel tar xf tool.tar.gz
sentinel unzip archive.zip
sentinel 7z x archive.7z
```

---

## Configuration

All options are set via environment variables:

| Variable | Default | Description |
|---|---|---|
| `SENTINEL_QUARANTINE` | `/tmp/sentinel-quarantine` | Directory infected files are moved into |
| `SENTINEL_CLAM_OPTS` | see below | Flags passed to `clamscan` (overrides all defaults) |
| `SENTINEL_SKIP_CLAM` | `0` | Set to `1` to skip ClamAV scan |
| `SENTINEL_SKIP_AUDIT` | `0` | Set to `1` to skip npm/composer audit |

**Default `clamscan` flags:**
```
--infected --suppress-ok-results
--heuristic-alerts --heuristic-scan-precedence
--alert-phishing-cloak --alert-phishing-ssl
--detect-pua
```

`--heuristic-scan-precedence` means a heuristic hit is reported immediately without waiting to finish all signature checks — this can make detections faster. The other heuristic flags extend coverage to packed/obfuscated binaries, phishing payloads, and potentially unwanted programs beyond the core signature database.

Setting `SENTINEL_CLAM_OPTS` replaces all of these defaults, so include `--infected --suppress-ok-results` in your override if you still want clean output.

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

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Clean — no threats found |
| `1` | The wrapped command itself failed |
| `2` | Malware detected — infected files quarantined |

Audit warnings (`npm audit`, `composer audit`) do not affect the exit code.

---

## CI / CD pipelines

In CI there is no interactive shell to source wrappers into — call `sentinel` directly. No shell wrappers or `install.sh` are needed; just copy the binary and add it to `PATH`.

### GitHub Actions

```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch sentinel
        run: |
          git clone https://github.com/geodro/sentinel.git /tmp/sentinel
          mkdir -p "$HOME/.local/bin"
          cp /tmp/sentinel/sentinel "$HOME/.local/bin/sentinel"
          chmod +x "$HOME/.local/bin/sentinel"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Cache ClamAV signatures
        uses: actions/cache@v4
        with:
          path: /var/lib/clamav
          key: clamav-${{ runner.os }}-${{ hashFiles('/var/lib/clamav/main.cvd') }}
          restore-keys: clamav-${{ runner.os }}-

      - name: Install ClamAV and update signatures
        run: |
          sudo apt-get install -y clamav
          sudo systemctl stop clamav-freshclam
          sudo freshclam

      - name: Install dependencies (with scan)
        run: sentinel npm install
        # composer: sentinel composer install
```

`$GITHUB_PATH` is the GitHub Actions mechanism for adding to `PATH` — equivalent to `export PATH=` in a local shell.

> **Tip:** If sentinel lives in the same repo as your project, replace the `Fetch sentinel` step with `cp sentinel "$HOME/.local/bin/sentinel"` — no clone needed.

### Bitbucket Pipelines

```yaml
# bitbucket-pipelines.yml
pipelines:
  default:
    - step:
        name: Install and scan dependencies
        image: node:20
        caches:
          - clamav
        script:
          - apt-get update && apt-get install -y clamav git
          - freshclam
          - git clone https://github.com/geodro/sentinel.git /tmp/sentinel
          - mkdir -p "$HOME/.local/bin"
          - cp /tmp/sentinel/sentinel "$HOME/.local/bin/sentinel"
          - chmod +x "$HOME/.local/bin/sentinel"
          - export PATH="$HOME/.local/bin:$PATH"
          - sentinel npm install
          # composer: sentinel composer install

definitions:
  caches:
    clamav: /var/lib/clamav
```

### CI notes

| Topic | Detail |
|---|---|
| Signature update time | `freshclam` adds ~1–2 min on a cold cache. Cache `/var/lib/clamav` between runs to avoid this. |
| Scan time | Large `node_modules`/`vendor` trees can be slow. Tune with `SENTINEL_CLAM_OPTS`. Project-tree scans only cover files written during the install run, so they are typically fast. |
| Audit exit codes | `npm audit` / `composer audit` are non-fatal (warnings only). |
| Malware detection | Exit code `2` — the build fails automatically. |
| Skipping checks | `SENTINEL_SKIP_CLAM=1` or `SENTINEL_SKIP_AUDIT=1` to bypass individual steps. |

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
for fn in git npm composer curl wget tar unzip 7z 7za; do
    rm -f ~/.config/fish/functions/$fn.fish
done
# Also remove the sentinel override block from ~/.config/fish/config.fish

# Zsh — remove the source line from ~/.zshrc
# Bash — remove the source line from ~/.bashrc
```
