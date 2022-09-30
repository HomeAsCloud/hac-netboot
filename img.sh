#!/bin/bash

function get_current_device() {
    local cur_device

    cur_device=$(losetup -f)
    echo $cur_device
}

function img_mount() {
    local cur_device=$1
    local img_file=$2
    local mapper_device
    local current

    losetup $cur_device $img_file
    if [ $? -ne 0 ]; then
        return 1
    fi
    kpartx -a $cur_device
    if [ $? -ne 0 ]; then
        losetup -d $cur_device
        return 1
    fi

    cur=1
    shift 2
    while [ ! -z "$1" ]; do
        mapper_device="/dev/mapper/$(basename $cur_device)p$cur"
        mount $mapper_device $1
        if [ $? -ne 0 ]; then
            img_unmount $cur_device
            return 1
        fi
        shift
        ((cur++))
    done

    return 0
}

function img_umount() {
    local cur_device=$1

    shift
    while [ ! -z "$1" ]; do
        umount $1 >&1 1>/dev/null
        shift
    done

    kpartx -d $cur_device
    losetup -d $cur_device
}
