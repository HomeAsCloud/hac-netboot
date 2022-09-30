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
        default_interface=$(ip route | grep default | awk '{print $5}')
        inet_address=$(ip address show $default_interface | grep 'inet ' | awk '{print $2}' | awk -F '/' '{print $1}')
        echo $inet_address
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
        default_interface=$(ip route | grep default | awk '{print $5}')
        inet_broadcast=$(ip address show $default_interface | grep 'inet ' | awk -F 'brd' '{print $2}' | awk '{print $1}')
        echo $inet_broadcast
    fi

    echo ''
}
