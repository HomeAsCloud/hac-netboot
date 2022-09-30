#!/bin/bash
g_device_module_path=''
g_device_module_names=''

function _get_module_names() {
    echo $g_device_module_names
}

function device_module_init() {
    g_device_module_path=$1
    g_device_module_names=$(ls $g_device_module_path)
    for m in $g_device_module_names; do
        source $g_device_module_path/$m
    done
}

function device_probe() {
    local line=$1
    local device_id
    local probe_success=0
    local modules=$(_get_module_names)

    for m in $modules; do
        m=${m:0:(${#m} - 3)}
        device_id=$(device_probe_${m} "$line")
        if [ ! -z $device_id ]; then
            probe_success=1
            break
        fi
    done

    if [ $probe_success -eq 0 ]; then
        echo
    else
        echo $device_id
    fi
}

function device_add() {
    local device_id=$1
    local modules=$(_get_module_names)

    for m in $modules; do
        m=${m:0:(${#m} - 3)}
        device_check_id_${m} $device_id
        if [ $? -eq 0 ]; then
            device_add_${m} $@
            return $?
        fi
    done

    return 1
}

function device_check_id() {
    local device_id=$1
    local modules=$(_get_module_names)

    for m in $modules; do
        m=${m:0:(${#m} - 3)}
        device_check_id_${m} $device_id
        if [ $? -eq 0 ]; then
            return $?
        fi
    done

    return 1
}
