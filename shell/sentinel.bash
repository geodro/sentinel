# sentinel — Bash shell wrappers
# Add to your ~/.bashrc or ~/.bash_profile:
#   source /path/to/sentinel/shell/sentinel.bash

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
