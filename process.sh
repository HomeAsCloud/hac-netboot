#!/bin/bash

declare -a g_process_list
g_process_last_id=-1

function process_new() {
    local pid

    $@ 3>&- &

    g_process_last_id=$!
    g_process_list[${#g_process_list[@]}]=$g_process_last_id
}

function process_get_last_id() {
    echo $g_process_last_id
}

function process_wait_all() {
    wait ${g_process_list[@]}
}

function _process_kill_all_impl() {
    local sudo=$1
    local ret=$($1 kill ${g_process_list[@]})

    unset g_process_list
    g_process_last_id=-1

    return $ret
}

function process_kill_all() {
    _process_kill_all_impl
    return $?
}

function process_kill_all_with_sudo() {
    _process_kill_all_impl sudo
    return $?
}
