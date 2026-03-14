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

function curl --wraps curl --description 'curl with ClamAV scanning on file downloads'
    sentinel curl $argv
end

function wget --wraps wget --description 'wget with ClamAV scanning on file downloads'
    sentinel wget $argv
end

function tar --wraps tar --description 'tar with ClamAV scanning on extract'
    set -l is_extract 0
    set -l first (count $argv > 0; and echo $argv[1]; or echo "")

    # Old-style (no leading dash): tar xf archive.tar.gz
    if string match -qv -- '-*' $first; and string match -q -- '*x*' $first
        set is_extract 1
    end

    if test $is_extract -eq 0
        for arg in $argv
            switch $arg
                case '--extract' '--get'
                    set is_extract 1
                case '-x'
                    set is_extract 1
                case '-*'
                    # Combined flags like -xzf
                    if string match -q -- '*x*' $arg
                        set is_extract 1
                    end
            end
            if test $is_extract -eq 1
                break
            end
        end
    end

    if test $is_extract -eq 1
        sentinel tar $argv
    else
        command tar $argv
    end
end

function unzip --wraps unzip --description 'unzip with ClamAV scanning on extract'
    sentinel unzip $argv
end

function 7z --wraps 7z --description '7z with ClamAV scanning on extract'
    set -l cmd (count $argv > 0; and echo $argv[1]; or echo "")
    if contains -- $cmd e x
        sentinel 7z $argv
    else
        command 7z $argv
    end
end

function 7za --wraps 7za --description '7za with ClamAV scanning on extract'
    set -l cmd (count $argv > 0; and echo $argv[1]; or echo "")
    if contains -- $cmd e x
        sentinel 7za $argv
    else
        command 7za $argv
    end
end
