#!/bin/bash

function _get_raspberrypi_id() {
    # dnsmasq-tftp[1628]: file /var/hac/tftproot/7092246e/start4.elf not found
    local id='[a-z0-9]{8}'
    local raspberrypi_id_pattern="dnsmasq-tftp.*/$id/start4.elf not found"
    local line=$1
    local ret

    ret=$(echo $line | grep -E "$raspberrypi_id_pattern")
    if [ $? -eq 0 ]; then
        ret=$(echo $line | grep -E -o "/$id/start4.elf" | awk -F '/' '{print $2}')
        echo $ret
    fi
}

function device_probe_raspberrypi() {
    local line=$1
    local device_id

    device_id=$(_get_raspberrypi_id "$line")
    if [ ! -z $device_id ]; then
        echo $device_id
    else
        echo
    fi
}

function device_check_id_raspberrypi() {
    local id='[a-z0-9]{8}'
    local line=$1
    local ret

    ret=$(echo $line | grep -E -o "^$id\$")
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function device_add_raspberrypi() {
    local device_id=$1
    local ip=$2
    local http_port=$3
    local nfs_path=$4
    local node_address=$5
    local node_gateway=$6
    local node_dns=$7
    local img_file="download/2022-09-06-raspios-bullseye-arm64-lite.img"
    local download_file="$img_file.xz"
    local rsa_public="/home/ubuntu/.ssh/authorized_keys"
    local tftproot="/var/hac/tftproot"
    local nfsroot="/var/hac/nfsroot"
    local temp
    local cur_device
    local node_ip

    log_info "installing bootloader"
    if [ -f $img_file -a -f $download_file ]; then
        rm -rf $img_file
    fi
    if [ ! -f $img_file ]; then
        log_info "  downloading raspberry-pi lite img"
        raspberry_lite_img_url="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2022-09-07/2022-09-06-raspios-bullseye-arm64-lite.img.xz"
        retry 3 download $raspberry_lite_img_url $download_file
        if [ $? -ne 0 ]; then
            log_error "  download raspberry-pi lite img error"
            return 1
        fi

        log_info "  extract raspberry-pi lite img"
        xz -d $download_file
        if [ $? -ne 0 ]; then
            log_error "  extract raspberry-pi lite xz error"
            return 1
        fi
    fi

    log_info "  mounting raspberry-pi lite img"
    # clear temp dir
    rm -rf download/boot
    mkdir -p download/boot
    rm -rf download/root
    mkdir -p download/root

    cur_device=$(get_current_device)
    img_mount $cur_device $img_file download/boot download/root
    if [ $? -ne 0 ]; then
        img_umount $cur_device
        log_error "  mount raspberry-pi lite img error"
        return 1
    fi

    log_info "  installing bootloader files"
    rm -rf $tftproot/$device_id
    mkdir -p $tftproot/$device_id
    cp -r download/boot/* $tftproot/$device_id

    log_info "installing nfs"
    log_info "  installing nfs files"
    rm -rf $nfsroot/$device_id
    mkdir -p $nfsroot/$device_id/boot
    cp -pr download/root/* $nfsroot/$device_id
    cp -pr download/boot/* $nfsroot/$device_id/boot

    log_info "  configuring ssh service"
    touch $nfsroot/$device_id/boot/ssh
    grep "^PasswordAuthentication no&" $nfsroot/$device_id/etc/ssh/sshd_config
    if [ $? -ne 0 ]; then
        echo "PasswordAuthentication no" >>$nfsroot/$device_id/etc/ssh/sshd_config
    fi

    log_info "  configuring ssh public"
    while true; do
        rsa_public=$(get_input "input your ssh public[$rsa_public]:" $rsa_public)
        if [ -f $rsa_public ]; then
            break
        else
            log_warn "$rsa_public not exist"
            continue
        fi
    done
    mkdir -p $nfsroot/$device_id/home/pi/.ssh/
    cat <<EOF | tee $nfsroot/$device_id/home/pi/.ssh/authorized_keys 2>&1 1>/dev/null
$(tail -n 1 $rsa_public)
EOF
    chmod 700 $nfsroot/$device_id/home/pi/.ssh/
    chmod 600 $nfsroot/$device_id/home/pi/.ssh/authorized_keys
    chown -R 1000.1000 $nfsroot/$device_id/home/pi/.ssh/

    log_info "  configuring network"
    if [ -z $node_address ]; then
        node_address=$(get_input "input node address(CIDR format-192.168.0.6/24):")
    else
            log_info "    configuring cloud-init: address is $node_address"
    fi
    if [ -z $node_gateway ]; then
        node_gateway=$(get_default_gateway)
        if [ -z $node_gateway ]; then
            node_gateway=$(get_input "input node gateway:")
        else
            log_info "    configuring network: gateway is $node_gateway"
        fi
    fi
    if [ -z $node_dns ]; then
        node_dns=$(get_default_dns)
        if [ -z $node_dns ]; then
            node_dns=$(get_input "input node dns:")
        else
            log_info "    configuring network: dns is $node_dns"
        fi
    fi
    grep "^interface eth0&" $nfsroot/$device_id/etc/dhcpcd.conf
    if [ $? -ne 0 ]; then
        echo "interface eth0" >>$nfsroot/$device_id/etc/dhcpcd.conf
        echo "static ip_address=$node_address" >>$nfsroot/$device_id/etc/dhcpcd.conf
        echo "static routers=$node_gateway" >>$nfsroot/$device_id/etc/dhcpcd.conf
        echo "static domain_name_servers=$node_dns" >>$nfsroot/$device_id/etc/dhcpcd.conf
    fi
    node_ip=$(echo $node_address | awk -F '/' '{print $1}')
    if [ $nfs_path == "auto" ]; then
        temp="$ip:/var/hac/nfsroot/$device_id"
    else
        temp="$nfs_path/$device_id"
    fi
    cat <<EOF | tee $tftproot/$device_id/cmdline.txt 2>&1 1>/dev/null
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$temp,vers=3 ip=$node_ip::::::dhcp rw rootwait elevator=deadline
EOF
    cat <<EOF | tee $nfsroot/$device_id/etc/hostname 2>&1 1>/dev/null
$device_id
EOF
    cat <<EOF | tee $nfsroot/$device_id/etc/hosts 2>&1 1>/dev/null
127.0.0.1 localhost
127.0.1.1 $device_id

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

    log_info "  configuring fstab"
    cat <<EOF | tee $nfsroot/$device_id/etc/fstab 2>&1 1>/dev/null
proc            /proc           proc    defaults          0       0
EOF

    log_info "  configuring iptables"
    rm $nfsroot/$device_id/usr/sbin/iptables
    cp $nfsroot/$device_id/usr/sbin/xtables-legacy-multi $nfsroot/$device_id/usr/sbin/iptables
    rm $nfsroot/$device_id/usr/sbin/iptables-restore
    cp $nfsroot/$device_id/usr/sbin/xtables-legacy-multi $nfsroot/$device_id/usr/sbin/iptables-restore
    rm $nfsroot/$device_id/usr/sbin/iptables-save
    cp $nfsroot/$device_id/usr/sbin/xtables-legacy-multi $nfsroot/$device_id/usr/sbin/iptables-save

    rm $nfsroot/$device_id/usr/sbin/ip6tables
    cp $nfsroot/$device_id/usr/sbin/xtables-nft-multi $nfsroot/$device_id/usr/sbin/ip6tables
    rm $nfsroot/$device_id/usr/sbin/ip6tables-restore
    cp $nfsroot/$device_id/usr/sbin/xtables-nft-multi $nfsroot/$device_id/usr/sbin/ip6tables-restore
    rm $nfsroot/$device_id/usr/sbin/ip6tables-save
    cp $nfsroot/$device_id/usr/sbin/xtables-nft-multi $nfsroot/$device_id/usr/sbin/ip6tables-save

    log_info "  umounting raspberry-pi lite img"
    img_umount $cur_device download/boot download/root
    # clear temp dir
    rm -rf download/boot
    rm -rf download/root

    return 0
}
