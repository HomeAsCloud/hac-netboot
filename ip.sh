#!/bin/bash

source util.sh

function get_default_ip() {
    local default_interface
    local inet_address

    is_darwin
    if [ $? -eq 0 ]; then
        default_interface=$(route -n get default | grep interface | awk '{print $2}')
        inet_address=$(ifconfig $default_interface | grep 'inet ' | awk '{print $2}')
        echo $inet_address
    else
        is_linux
        if [ $? -eq 0 ]; then
            default_interface=$(ip route | grep default | awk '{print $5}')
            inet_address=$(ip address show $default_interface | grep 'inet ' | awk '{print $2}' | awk -F '/' '{print $1}')
            echo $inet_address
        fi
    fi

    echo ''
}

function get_default_broadcast() {
    local default_interface
    local inet_broadcast

    is_darwin
    if [ $? -eq 0 ]; then
        default_interface=$(route -n get default | grep interface | awk '{print $2}')
        inet_broadcast=$(ifconfig $default_interface | grep 'inet ' | awk '{print $6}')
        echo $inet_broadcast
    else
        is_linux
        if [ $? -eq 0 ]; then
            default_interface=$(ip route | grep default | awk '{print $5}')
            inet_broadcast=$(ip address show $default_interface | grep 'inet ' | awk -F 'brd' '{print $2}' | awk '{print $1}')
            echo $inet_broadcast
        fi
    fi

    echo ''
}

function get_default_gateway() {
    local gateway

    is_darwin
    if [ $? -eq 0 ]; then
        gateway=$(route -n get default | grep gateway | awk '{print $2}')
        echo $gateway
    else
        is_linux
        if [ $? -eq 0 ]; then
            gateway=$(ip route | grep default | awk '{print $3}')
            echo $gateway
        fi
    fi

    echo ''
}

function get_default_dns() {
    local dns

    is_darwin
    if [ $? -eq 0 ]; then
        dns=$(scutil --dns | grep nameserver | tail -n 1 | awk '{print $3}')
        echo $dns
    else
        is_linux
        if [ $? -eq 0 ]; then
            dns=$(resolvectl | grep 'Current DNS Server' | awk -F ':' '{print $2}')
            echo $dns
        fi
    fi

    echo ''
}
