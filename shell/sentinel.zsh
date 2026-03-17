# sentinel — Zsh shell wrappers
# Add to your ~/.zshrc:
#   source /path/to/sentinel/shell/sentinel.zsh

git() {
    local cmd="${1:-}"
    case "$cmd" in
        clone|pull|fetch)
            sentinel git "$@"
            ;;
        *)
            command git "$@"
            ;;
    esac
}

npm() {
    local cmd="${1:-}"
    case "$cmd" in
        install|i|ci|update|up)
            sentinel npm "$@"
            ;;
        *)
            command npm "$@"
            ;;
    esac
}

composer() {
    local cmd="${1:-}"
    case "$cmd" in
        install|update|require)
            sentinel composer "$@"
            ;;
        *)
            command composer "$@"
            ;;
    esac
}

curl() {
    sentinel curl "$@"
}

bash() {
    sentinel bash "$@"
}

wget() {
    sentinel wget "$@"
}

tar() {
    local first="${1:-}"
    local is_extract=0

    # Old-style (no leading dash): tar xf archive.tar.gz
    if [[ "$first" != -* && "$first" == *x* ]]; then
        is_extract=1
    else
        for arg in "$@"; do
            case "$arg" in
                --extract|--get) is_extract=1; break ;;
                # Combined flags like -xzf or standalone -x
                -*) [[ "$arg" == *x* ]] && { is_extract=1; break; } ;;
            esac
        done
    fi

    if [[ $is_extract -eq 1 ]]; then
        sentinel tar "$@"
    else
        command tar "$@"
    fi
}

unzip() {
    sentinel unzip "$@"
}

7z() {
    local cmd="${1:-}"
    case "$cmd" in
        e|x) sentinel 7z "$@" ;;
        *)   command 7z "$@" ;;
    esac
}

7za() {
    local cmd="${1:-}"
    case "$cmd" in
        e|x) sentinel 7za "$@" ;;
        *)   command 7za "$@" ;;
    esac
}
