# sentinel — Fish shell wrappers
# Source or copy into ~/.config/fish/functions/
# Each function must be saved as its own file named after the function.

function git --wraps git --description 'git with ClamAV scanning on clone/pull/fetch'
    set -l cmd (count $argv > 0; and echo $argv[1]; or echo "")
    if contains -- $cmd clone pull fetch
        sentinel git $argv
    else
        command git $argv
    end
end

function npm --wraps npm --description 'npm with ClamAV + audit scanning on install'
    set -l cmd (count $argv > 0; and echo $argv[1]; or echo "")
    if contains -- $cmd install i ci update up
        sentinel npm $argv
    else
        command npm $argv
    end
end

function composer --wraps composer --description 'composer with ClamAV + audit scanning on install'
    set -l cmd (count $argv > 0; and echo $argv[1]; or echo "")
    if contains -- $cmd install update require
        sentinel composer $argv
    else
        command composer $argv
    end
end
