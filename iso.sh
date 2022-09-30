#!/bin/bash

function _iso_mount() {
    local iso_file=$1
    local mount_dir=$2
    local temp
    local disk
    local SUDO=sudo
    [ "$(id -u)" = "0" ] && SUDO=

    is_darwin
    if [ $? -eq 0 ]; then
        temp=$(hdiutil attach -nomount $iso_file | grep GUID_partition_scheme)
        if [ $? -eq 0 ]; then
            disk=$(echo $temp | awk '{print $1}')
            mount -t cd9660 $disk $mount_dir
            if [ $? -eq 0 ]; then
                return 0
            fi
        fi
    else
        is_linux
        if [ $? -eq 0 ]; then
            $SUDO cat /dev/null
            $SUDO mount -o loop $iso_file $mount_dir
            if [ $? -eq 0 ]; then
                return 0
            fi
        fi
    fi

    return 1
}

function _iso_unmount() {
    local mount_dir=$1
    local disk
    local SUDO=sudo
    [ "$(id -u)" = "0" ] && SUDO=

    is_darwin
    if [ $? -eq 0 ]; then
        temp=$(hdiutil attach -nomount $iso_file | grep GUID_partition_scheme)
        if [ $? -eq 0 ]; then
            disk=$(echo $temp | awk '{print $1}')
            umount $mount_dir 2>/dev/null
            hdiutil detach $disk 2>/dev/null
            return 0
        fi
    else
        is_linux
        if [ $? -eq 0 ]; then
            $SUDO cat /dev/null
            $SUDO umount $mount_dir
            if [ $? -eq 0 ]; then
                return 0
            fi
        fi
    fi

    return 1
}

function iso_extract() {
    local iso_file=$1
    shift
    local extract_files=$@
    local mount_ret=0
    local cp_ret=0
    local mount_dir='iso'

    mkdir -p $mount_dir
    _iso_mount $iso_file $mount_dir
    if [ $? -ne 0 ]; then
        mount_ret=1
    fi

    if [ $mount_ret -eq 0 ]; then
        for f in $extract_files; do
            mkdir -p $(dirname $f)
            cp $mount_dir/$f $f
            if [ $? -ne 0 ]; then
                cp_ret=1
            fi
        done
    fi

    _iso_unmount $mount_dir
    rm -rf $mount_dir

    if [ $cp_ret -ne 0 ]; then
        return 1
    fi
    if [ $mount_ret -ne 0 ]; then
        return 1
    fi
    return 0
}
