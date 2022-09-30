#!/bin/bash

function service_enable_if_disabled() {
    local s=$1
    systemctl is-enabled $s 2>&1 1>/dev/null
    if [ $? -ne 0 ]; then
        systemctl enable $s
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    return 0
}

function service_restart() {
    local s=$1

    systemctl restart $s
    if [ $? -ne 0 ]; then
        return 1
    else
        return 0
    fi
}

function service_restart_if_inactive() {
    local s=$1

    systemctl is-active $s 2>&1 1>/dev/null
    if [ $? -ne 0 ]; then
        service_restart $s
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    return 0
}
