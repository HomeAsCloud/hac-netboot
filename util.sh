#!/bin/bash
source log.sh

function retry() {
    local times=$1
    local func=$2
    shift 2
    local args=$@
    local current=$times

    while (($current > 0)); do
        eval $func $args
        if [ $? -ne 0 ]; then
            log_warn "retry $(($times - $current + 1)): $func $args"
            ((current--))
        else
            break
        fi
    done
}

function is_darwin() { [[ $OSTYPE =~ darwin* ]]; }
function is_linux() { [[ $OSTYPE =~ linux* ]]; }

function download() {
    local url=$1
    local out=$2

    wget -c $url -O $out
}

function extract_from_tar() {
    local tar_file=$1
    shift
    local extract_files=$@

    tar xf $tar_file $extract_files
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function has_command() {
    local cmd=$1

    if ! type $cmd >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

function get_input() {
    local prompt=$1
    local default=$2
    local temp

    while true; do
        echo -n $prompt >&2
        read temp
        if [ ! -z $temp ]; then
            echo $temp
            break
        else
            if [ ! -z $default ]; then
                echo $default
                break
            fi
        fi
    done
}
