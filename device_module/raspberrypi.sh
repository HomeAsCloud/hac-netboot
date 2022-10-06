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
    local node_address=$4
    local node_gateway=$5
    local node_dns=$6
    local img_file="download/2022-09-06-raspios-bullseye-arm64-lite.img"
    local download_file="$img_file.xz"
    local rsa_public="/home/ubuntu/.ssh/authorized_keys"
    local tftproot="/var/hac/tftproot"
    local iscsiroot="/var/hac/iscsiroot"
    local iscsi_img_size_g=16
    local iscsi_iqn="iqn.2022-10.com.homeascloud:rpi"
    local temp
    local cur_device
    local node_ip
    local iscsi_img_uuid

    log_info "installing raspberry-pi"
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

    log_info "  installing tftp files"
    rm -rf $tftproot/$device_id
    mkdir -p $tftproot/$device_id
    cp -r download/boot/* $tftproot/$device_id
    cp -r ../initrd.img-5.15.61-v8+ $tftproot/$device_id
    log_info "  configuring tftp"
    grep "^initramfs initrd.img-5.15.61-v8+ followkernel&" $tftproot/$device_id/config.txt
    if [ $? -ne 0 ]; then
        echo "initramfs initrd.img-5.15.61-v8+ followkernel" >>$tftproot/$device_id/config.txt
    fi

    log_info "  installing iscsi img"
    log_info "    create iscsi img"
    rm -rf $iscsiroot/$device_id.img
    dd if=/dev/zero of=$iscsiroot/$device_id.img bs=1M count=${iscsi_img_size_g}000
    log_info "    mount iscsi img"
    rm -rf $iscsiroot/$device_id
    mkdir -p $iscsiroot/$device_id
    mkfs.ext4 $iscsiroot/$device_id.img
    blkid $iscsiroot/$device_id.img
    mount $iscsiroot/$device_id.img $iscsiroot/$device_id
    log_info "    install iscsi files"
    cp -pr download/root/* $iscsiroot/$device_id

    log_info "    configuring ssh service"
    mkdir -p $iscsiroot/$device_id/boot
    touch $iscsiroot/$device_id/boot/ssh
    grep "^PasswordAuthentication no&" $iscsiroot/$device_id/etc/ssh/sshd_config
    if [ $? -ne 0 ]; then
        echo "PasswordAuthentication no" >>$iscsiroot/$device_id/etc/ssh/sshd_config
    fi

    log_info "    configuring ssh public"
    while true; do
        rsa_public=$(get_input "input your ssh public[$rsa_public]:" $rsa_public)
        if [ -f $rsa_public ]; then
            break
        else
            log_warn "$rsa_public not exist"
            continue
        fi
    done
    mkdir -p $iscsiroot/$device_id/home/pi/.ssh/
    cat <<EOF | tee $iscsiroot/$device_id/home/pi/.ssh/authorized_keys 2>&1 1>/dev/null
$(tail -n 1 $rsa_public)
EOF
    chmod 700 $iscsiroot/$device_id/home/pi/.ssh/
    chmod 600 $iscsiroot/$device_id/home/pi/.ssh/authorized_keys
    chown -R 1000.1000 $iscsiroot/$device_id/home/pi/.ssh/

    log_info "    configuring network"
    if [ -z $node_address ]; then
        node_address=$(get_input "input node address(CIDR format-192.168.0.6/24):")
    else
            log_info "      configuring network: address is $node_address"
    fi
    if [ -z $node_gateway ]; then
        node_gateway=$(get_default_gateway)
        if [ -z $node_gateway ]; then
            node_gateway=$(get_input "input node gateway:")
        else
            log_info "      configuring network: gateway is $node_gateway"
        fi
    fi
    if [ -z $node_dns ]; then
        node_dns=$(get_default_dns)
        if [ -z $node_dns ]; then
            node_dns=$(get_input "input node dns:")
        else
            log_info "      configuring network: dns is $node_dns"
        fi
    fi
    grep "^interface eth0&" $iscsiroot/$device_id/etc/dhcpcd.conf
    if [ $? -ne 0 ]; then
        echo "interface eth0" >>$iscsiroot/$device_id/etc/dhcpcd.conf
        echo "static ip_address=$node_address" >>$iscsiroot/$device_id/etc/dhcpcd.conf
        echo "static routers=$node_gateway" >>$iscsiroot/$device_id/etc/dhcpcd.conf
        echo "static domain_name_servers=$node_dns" >>$iscsiroot/$device_id/etc/dhcpcd.conf
    fi
    node_ip=$(echo $node_address | awk -F '/' '{print $1}')
    iscsi_img_uuid=$(blkid $iscsiroot/$device_id.img | grep -o -E '\w{8}(-\w{4}){3}-\w{12}')
    cat <<EOF | tee $tftproot/$device_id/cmdline.txt 2>&1 1>/dev/null
console=serial0,115200 console=tty1 root=UUID=$iscsi_img_uuid rootfstype=ext4 ip=$node_ip::::::dhcp rw rootwait elevator=deadline fsck.repair=yes cgroup_memory=1 cgroup_enable=memory ISCSI_INITIATOR=$iscsi_iqn-$device_id ISCSI_TARGET_NAME=$iscsi_iqn ISCSI_TARGET_IP=$ip ISCSI_TARGET_PORT=3260
EOF
    cat <<EOF | tee $iscsiroot/$device_id/etc/hostname 2>&1 1>/dev/null
$device_id
EOF
    cat <<EOF | tee $iscsiroot/$device_id/etc/hosts 2>&1 1>/dev/null
127.0.0.1 localhost
127.0.1.1 $device_id

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

    log_info "    configuring fstab"
    cat <<EOF | tee $iscsiroot/$device_id/etc/fstab 2>&1 1>/dev/null
proc            /proc           proc    defaults          0       0
EOF

    log_info "    configuring iptables"
    rm $iscsiroot/$device_id/usr/sbin/iptables
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/iptables
    rm $iscsiroot/$device_id/usr/sbin/iptables-restore
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/iptables-restore
    rm $iscsiroot/$device_id/usr/sbin/iptables-save
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/iptables-save

    rm $iscsiroot/$device_id/usr/sbin/ip6tables
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/ip6tables
    rm $iscsiroot/$device_id/usr/sbin/ip6tables-restore
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/ip6tables-restore
    rm $iscsiroot/$device_id/usr/sbin/ip6tables-save
    cp $iscsiroot/$device_id/usr/sbin/xtables-legacy-multi $iscsiroot/$device_id/usr/sbin/ip6tables-save

    log_info "    configuring iscsi"
    sudo targetcli iscsi/ create "$iscsi_iqn"
    sudo targetcli backstores/fileio/ delete $device_id
    sudo targetcli backstores/fileio/ create $device_id $iscsiroot/$device_id.img ${iscsi_img_size_g}G
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/luns/" delete "/backstores/fileio/$device_id"
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/luns/" create "/backstores/fileio/$device_id"
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/acls/" delete "$iscsi_iqn-$device_id"
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/acls/" create "$iscsi_iqn-$device_id"
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/" set attribute generate_node_acls=1
    sudo targetcli "iscsi/$iscsi_iqn/tpg1/" set attribute demo_mode_write_protect=0
    sudo targetcli saveconfig
    log_info "    umounting iscsi img"
    umount $iscsiroot/$device_id

    log_info "  umounting raspberry-pi lite img"
    img_umount $cur_device download/boot download/root
    # clear temp dir
    rm -rf download/boot
    rm -rf download/root

    return 0
}
