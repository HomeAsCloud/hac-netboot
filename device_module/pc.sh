#!/bin/bash

function _get_syslinux_mac_id() {
    # dnsmasq-tftp[954]: file /var/hac/tftproot/efi64/pxelinux.cfg/01-00-0c-29-4f-62-c7 not found
    local id='\w{2}(-\w{2}){6}'
    local mac_id_pattern="dnsmasq-tftp.*pxelinux.cfg/$id not found"
    local line=$1
    local ret

    ret=$(echo $line | grep -E "$mac_id_pattern" | grep -E -o "$id")
    if [ $? -eq 0 ]; then
        echo $ret
    fi
}

function device_probe_pc() {
    local line=$1
    local device_id

    device_id=$(_get_syslinux_mac_id "$line")
    if [ ! -z $device_id ]; then
        echo $device_id
    else
        echo
    fi
}

function device_check_id_pc() {
    local id='\w{2}(-\w{2}){6}'
    local line=$1
    local ret

    ret=$(echo $line | grep -E -o "^$id\$")
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function device_add_pc() {
    local device_id=$1
    local ip=$2
    local http_port=$3
    local nfs_path=$4
    local node_address=$5
    local node_gateway=$6
    local node_dns=$7
    local download_file="download/ubuntu-22.04.1-live-server-amd64.iso"
    local rsa_public="/home/ubuntu/.ssh/authorized_keys"
    local tftproot="/var/hac/tftproot"
    local httproot="/var/hac/httproot"
    local temp

    # http
    #  install iso, vmlinuz/initrd
    #  configure cloud-init user-data
    log_info "installing http"
    log_info "  downloading ubuntu live iso"
    ubuntu_live_iso_url="https://releases.ubuntu.com/22.04/ubuntu-22.04.1-live-server-amd64.iso"
    retry 3 download $ubuntu_live_iso_url $download_file
    if [ $? -ne 0 ]; then
        log_error "  download ubuntu live iso error"
        return 1
    fi

    log_info "  extracting ubuntu live iso"
    rm -rf casper
    iso_extract $download_file casper/vmlinuz casper/initrd
    if [ $? -ne 0 ]; then
        log_error "  extract vmlinuz and initrd error"
        return 1
    fi

    log_info "  install ubuntu live iso"
    if [ ! -f $httproot/$(basename $download_file) ]; then
        cp -f $download_file $httproot/
    fi
    mkdir -p $httproot/$device_id
    rm -rf $httproot/$device_id/casper
    mv -f casper $httproot/$device_id
    rm -rf $httproot/$device_id/$(basename $download_file)
    ln -s $httproot/$(basename $download_file) $httproot/$device_id/$(basename $download_file)

    log_info "  configuring cloud-init"
    while true; do
        temp=$(get_input "input your ssh public[$rsa_public]:" $rsa_public)
        if [ -f $temp ]; then
            rsa_public=$temp
            break
        else
            log_warn "$temp not exist"
            continue
        fi
    done
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
            log_info "    configuring cloud-init: gateway is $node_gateway"
        fi
    fi
    if [ -z $node_dns ]; then
        node_dns=$(get_default_dns)
        if [ -z $node_dns ]; then
            node_dns=$(get_input "input node dns:")
        else
            log_info "    configuring cloud-init: dns is $node_dns"
        fi
    fi
    mkdir -p $httproot/$device_id/cloud-init/
    touch $httproot/$device_id/cloud-init/meta-data
    cat <<EOF | tee $httproot/$device_id/cloud-init/user-data
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: $device_id
    username: ubuntu
    password: '\$6\$exDY1mhS4KUYCE/2\$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0'
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - $(tail -n 1 $rsa_public)
  network:
    version: 2
    ethernets:
      eth0:
        match:
          name: e*
        addresses:
          - $node_address
        gateway4: $node_gateway
        nameservers:
          addresses:
            - $node_dns
  late-commands:
    - |
      cat <<EOF | sudo tee /target/etc/sudoers.d/010_ubuntu-nopasswd
      ubuntu ALL=(ALL) NOPASSWD:ALL
      EOF
    - curtin in-target --target /target chmod 440 /etc/sudoers.d/010_ubuntu-nopasswd
    - curtin in-target --target /target -- update-alternatives --set iptables /usr/sbin/iptables-legacy
    - curtin in-target --target /target -- update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
EOF

    # bootloader
    mkdir -p $tftproot/pxelinux.cfg
    cat <<EOF | tee $tftproot/pxelinux.cfg/$device_id 2>&1 1>/dev/null
DEFAULT install
LABEL install
  KERNEL http://$ip:$http_port/$device_id/casper/vmlinuz
  INITRD http://$ip:$http_port/$device_id/casper/initrd
  APPEND root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://$ip:$http_port/$device_id/ubuntu-22.04.1-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://$ip:$http_port/$device_id/cloud-init/
}
EOF
    mkdir -p $tftproot/efi64/pxelinux.cfg
    rm -rf $tftproot/efi64/pxelinux.cfg/$device_id
    ln -s $tftproot/pxelinux.cfg/$device_id $tftproot/efi64/pxelinux.cfg/$device_id
    mkdir -p $tftproot/efi32/pxelinux.cfg
    rm -rf $tftproot/efi32/pxelinux.cfg/$device_id
    ln -s $tftproot/pxelinux.cfg/$device_id $tftproot/efi32/pxelinux.cfg/$device_id

    return 0
}
