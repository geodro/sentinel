#!/usr/bin/env bash
# tests/test_commands.sh
# Integration tests for sentinel's per-command scan handlers:
# git (clone/pull/fetch), curl, wget, tar, unzip, 7z/7za

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
        fail "$label" "expected: '$needle'"
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

make_env() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/bin" "$dir/project"

    # system utilities needed under isolated PATH
    #   basename — used by curl_output_path and git_clone_target_dir
    #   mkdir    — quarantine dir creation
    #   mktemp   — INSTALL_TIMESTAMP (npm/composer paths; harmless here)
    #   rm       — timestamp cleanup
    for cmd in bash mkdir mktemp rm basename cat; do
        local p; p="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -sf "$p" "$dir/bin/$cmd" || true
    done

    # fake clamscan: log args, always clean
    cat > "$dir/bin/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "CLAMSCAN $*" >> "$CLAMSCAN_LOG"
exit 0
EOF
    chmod +x "$dir/bin/clamscan"

    # trivial fakes for every supported command
    for cmd in git curl wget tar unzip 7z 7za; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/$cmd"
        chmod +x "$dir/bin/$cmd"
    done

    echo "$dir"
}

scan_log() { cat "$1/clamscan.log" 2>/dev/null || true; }

# Run: sentinel <args…>  inside the project dir with isolated PATH.
# Sets SENTINEL_OUTPUT; returns sentinel's exit code.
SENTINEL_OUTPUT=""
run_cmd() {
    local env_dir="$1"
    local extra_env="${2:-}"
    shift 2
    local log="$env_dir/clamscan.log"
    > "$log"

    local exit_code=0
    SENTINEL_OUTPUT=$(
        cd "$env_dir/project"
        export CLAMSCAN_LOG="$log"
        export PATH="$env_dir/bin"
        [[ -n "$extra_env" ]] && eval "export $extra_env"
        "$SENTINEL_BIN" "$@" 2>&1
    ) || exit_code=$?
    return $exit_code
}

# ── git ───────────────────────────────────────────────────────────────────────

echo ""
echo "=== git ==="
echo ""

echo "--- 1: git clone scans directory derived from URL ---"
E=$(make_env)
mkdir -p "$E/project/repo"
run_cmd "$E" "" git clone https://example.com/repo.git || true
assert_contains "git clone: derived dir scanned" "$(scan_log "$E")" "repo"
rm -rf "$E"

echo ""
echo "--- 2: git clone scans explicit target directory ---"
E=$(make_env)
mkdir -p "$E/project/mydir"
run_cmd "$E" "" git clone https://example.com/repo.git mydir || true
assert_contains "git clone: explicit dir scanned" "$(scan_log "$E")" "mydir"
rm -rf "$E"

echo ""
echo "--- 3: git pull scans current directory ---"
E=$(make_env)
run_cmd "$E" "" git pull || true
assert_contains "git pull: cwd scanned" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 4: git fetch scans current directory ---"
E=$(make_env)
run_cmd "$E" "" git fetch || true
assert_contains "git fetch: cwd scanned" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 5: git commit passes through without scanning ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" git commit -m "msg" || exit_code=$?
assert_exit         "git commit: exit 0"   "$exit_code" "0"
assert_not_contains "git commit: no scan"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 6: git clone: infected repo causes exit 2 ---"
E=$(make_env)
mkdir -p "$E/project/repo"
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" git clone https://example.com/repo.git || exit_code=$?
assert_exit "git clone: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 7: SENTINEL_SKIP_CLAM=1 skips git clone scan ---"
E=$(make_env)
mkdir -p "$E/project/repo"
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" git clone https://example.com/repo.git || true
assert_not_contains "git clone: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── curl ──────────────────────────────────────────────────────────────────────

echo ""
echo "=== curl ==="
echo ""

echo "--- 8: curl -o: scans the output file ---"
E=$(make_env)
touch "$E/project/file.zip"
run_cmd "$E" "" curl -o file.zip https://example.com/file.zip || true
assert_contains "curl -o: output file scanned" "$(scan_log "$E")" "file.zip"
rm -rf "$E"

echo ""
echo "--- 9: curl -O: scans filename derived from URL ---"
E=$(make_env)
touch "$E/project/archive.tar.gz"
run_cmd "$E" "" curl -O https://example.com/archive.tar.gz || true
assert_contains "curl -O: derived filename scanned" "$(scan_log "$E")" "archive.tar.gz"
rm -rf "$E"

echo ""
echo "--- 10: curl without -o/-O pipes to stdout — scans content first ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" curl https://example.com/data || exit_code=$?
assert_exit     "curl piped stdout: exit 0"   "$exit_code" "0"
assert_contains "curl piped stdout: scanned"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 11: curl -o: infected download causes exit 2 ---"
E=$(make_env)
touch "$E/project/malware.zip"
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" curl -o malware.zip https://example.com/malware.zip || exit_code=$?
assert_exit "curl -o: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 12: SENTINEL_SKIP_CLAM=1 skips curl scan ---"
E=$(make_env)
touch "$E/project/file.zip"
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" curl -o file.zip https://example.com/file.zip || true
assert_not_contains "curl: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── wget ──────────────────────────────────────────────────────────────────────

echo ""
echo "=== wget ==="
echo ""

echo "--- 13: wget <url>: scans filename derived from URL ---"
E=$(make_env)
touch "$E/project/archive.zip"
run_cmd "$E" "" wget https://example.com/archive.zip || true
assert_contains "wget url: derived filename scanned" "$(scan_log "$E")" "archive.zip"
rm -rf "$E"

echo ""
echo "--- 14: wget -O file: scans the explicit output file ---"
E=$(make_env)
touch "$E/project/output.zip"
run_cmd "$E" "" wget -O output.zip https://example.com/something || true
assert_contains "wget -O: output file scanned" "$(scan_log "$E")" "output.zip"
rm -rf "$E"

echo ""
echo "--- 15: wget -P dir: scans the download directory ---"
E=$(make_env)
mkdir -p "$E/project/downloads"
run_cmd "$E" "" wget -P downloads https://example.com/file.zip || true
assert_contains "wget -P: directory scanned" "$(scan_log "$E")" "downloads"
rm -rf "$E"

echo ""
echo "--- 16: wget -O - pipes to stdout — scans content first ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" wget -O - https://example.com/file || exit_code=$?
assert_exit     "wget piped stdout: exit 0"   "$exit_code" "0"
assert_contains "wget piped stdout: scanned"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 17: wget: infected download causes exit 2 ---"
E=$(make_env)
touch "$E/project/malware.zip"
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" wget -O malware.zip https://example.com/malware.zip || exit_code=$?
assert_exit "wget: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

# ── tar ───────────────────────────────────────────────────────────────────────

echo ""
echo "=== tar ==="
echo ""

echo "--- 18: tar xf: scans current directory by default ---"
E=$(make_env)
run_cmd "$E" "" tar xf archive.tar.gz || true
assert_contains "tar xf: cwd scanned" "$(scan_log "$E")" "CLAMSCAN -r ."
rm -rf "$E"

echo ""
echo "--- 19: tar xf -C dir: scans the target directory ---"
E=$(make_env)
mkdir -p "$E/project/extracted"
run_cmd "$E" "" tar xf archive.tar.gz -C extracted || true
assert_contains "tar -C: target dir scanned" "$(scan_log "$E")" "extracted"
rm -rf "$E"

echo ""
echo "--- 20: tar: infected extraction causes exit 2 ---"
E=$(make_env)
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" tar xf archive.tar.gz || exit_code=$?
assert_exit "tar: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 21: SENTINEL_SKIP_CLAM=1 skips tar scan ---"
E=$(make_env)
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" tar xf archive.tar.gz || true
assert_not_contains "tar: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── unzip ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== unzip ==="
echo ""

echo "--- 22: unzip: scans current directory by default ---"
E=$(make_env)
run_cmd "$E" "" unzip archive.zip || true
assert_contains "unzip: cwd scanned" "$(scan_log "$E")" "CLAMSCAN -r ."
rm -rf "$E"

echo ""
echo "--- 23: unzip -d dir: scans the target directory ---"
E=$(make_env)
mkdir -p "$E/project/out"
run_cmd "$E" "" unzip archive.zip -d out || true
assert_contains "unzip -d: target dir scanned" "$(scan_log "$E")" "out"
rm -rf "$E"

echo ""
echo "--- 24: unzip: infected extraction causes exit 2 ---"
E=$(make_env)
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" unzip archive.zip || exit_code=$?
assert_exit "unzip: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 25: SENTINEL_SKIP_CLAM=1 skips unzip scan ---"
E=$(make_env)
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" unzip archive.zip || true
assert_not_contains "unzip: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── 7z / 7za ──────────────────────────────────────────────────────────────────

echo ""
echo "=== 7z / 7za ==="
echo ""

echo "--- 26: 7z x: scans current directory by default ---"
E=$(make_env)
run_cmd "$E" "" 7z x archive.7z || true
assert_contains "7z x: cwd scanned" "$(scan_log "$E")" "CLAMSCAN -r ."
rm -rf "$E"

echo ""
echo "--- 27: 7z x -o/dir: scans the target directory ---"
E=$(make_env)
mkdir -p "$E/project/out7z"
run_cmd "$E" "" 7z x archive.7z -oout7z || true
assert_contains "7z -o: target dir scanned" "$(scan_log "$E")" "out7z"
rm -rf "$E"

echo ""
echo "--- 28: 7z e: also scans (extract subcommand) ---"
E=$(make_env)
run_cmd "$E" "" 7z e archive.7z || true
assert_contains "7z e: cwd scanned" "$(scan_log "$E")" "CLAMSCAN -r ."
rm -rf "$E"

echo ""
echo "--- 29: 7za x: scans current directory by default ---"
E=$(make_env)
run_cmd "$E" "" 7za x archive.7z || true
assert_contains "7za x: cwd scanned" "$(scan_log "$E")" "CLAMSCAN -r ."
rm -rf "$E"

echo ""
echo "--- 30: 7z x: infected extraction causes exit 2 ---"
E=$(make_env)
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
exit_code=0
run_cmd "$E" "" 7z x archive.7z || exit_code=$?
assert_exit "7z x: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 31: SENTINEL_SKIP_CLAM=1 skips 7z scan ---"
E=$(make_env)
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" 7z x archive.7z || true
assert_not_contains "7z: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── wget combined short options ───────────────────────────────────────────────

echo ""
echo "=== wget combined short options ==="
echo ""

echo "--- 32: wget -O- pipes to stdout — scans content first ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" wget -O- https://example.com/file || exit_code=$?
assert_exit     "wget -O- piped: exit 0"   "$exit_code" "0"
assert_contains "wget -O- piped: scanned"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 33: wget -qO- pipes to stdout — scans content first ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" wget -qO- https://example.com/install.sh || exit_code=$?
assert_exit     "wget -qO- piped: exit 0"   "$exit_code" "0"
assert_contains "wget -qO- piped: scanned"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── bash ──────────────────────────────────────────────────────────────────────

echo ""
echo "=== bash ==="
echo ""

echo "--- 34: bash <(process substitution): FIFO — scans fd content ---"
E=$(make_env)
# Simulate process substitution by creating a named pipe (FIFO) and writing to it
# before sentinel reads it.  On Linux, bash <(...) uses /dev/fd/NN (a pipe);
# on some systems it uses a FIFO — we cover both with the -p check in handle_bash.
FIFO="$(mktemp -u /tmp/sentinel-test-fd-XXXXXX)"
mkfifo "$FIFO"
# Write script content to the FIFO in the background so the reader doesn't block
printf '#!/usr/bin/env bash\necho hello\n' > "$FIFO" &
WRITER_PID=$!
run_cmd "$E" "" bash "$FIFO" || true
wait "$WRITER_PID" 2>/dev/null || true
assert_contains "bash FIFO: scanned" "$(scan_log "$E")" "CLAMSCAN"
rm -f "$FIFO"
rm -rf "$E"

echo ""
echo "--- 35: bash script.sh: regular script file — scans before execution ---"
E=$(make_env)
SCRIPT="$E/project/install.sh"
echo '#!/usr/bin/env bash' > "$SCRIPT"
echo 'echo hello' >> "$SCRIPT"
run_cmd "$E" "" bash "$SCRIPT" || true
assert_contains "bash script.sh: scanned" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 36: bash -c: inline command — passes through without scan ---"
E=$(make_env)
exit_code=0
run_cmd "$E" "" bash -c "echo hello" || exit_code=$?
assert_exit         "bash -c: exit 0"   "$exit_code" "0"
assert_not_contains "bash -c: no scan"  "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

echo ""
echo "--- 37: bash script.sh: infected script causes exit 2 ---"
E=$(make_env)
printf '#!/usr/bin/env bash\necho "CLAMSCAN $*" >> "$CLAMSCAN_LOG"\nexit 1\n' > "$E/bin/clamscan"
chmod +x "$E/bin/clamscan"
SCRIPT="$E/project/malware.sh"
echo '#!/usr/bin/env bash' > "$SCRIPT"
exit_code=0
run_cmd "$E" "" bash "$SCRIPT" || exit_code=$?
assert_exit "bash script: infected → exit 2" "$exit_code" "2"
rm -rf "$E"

echo ""
echo "--- 38: SENTINEL_SKIP_CLAM=1 skips bash script scan ---"
E=$(make_env)
SCRIPT="$E/project/install.sh"
echo '#!/usr/bin/env bash' > "$SCRIPT"
run_cmd "$E" "SENTINEL_SKIP_CLAM=1" bash "$SCRIPT" || true
assert_not_contains "bash: skip clam" "$(scan_log "$E")" "CLAMSCAN"
rm -rf "$E"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""
[[ $FAIL -eq 0 ]]
