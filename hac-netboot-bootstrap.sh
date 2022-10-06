#!/bin/bash
source iso.sh
source ip.sh
source log.sh
source process.sh
source util.sh

function usage() {
    log "uasge: $(basename $0) [options]"
    log "  -h,--help          print this help message"
    log "  --server-address   address of static network(CIDR format. example: 192.168.0.6/24)"
    log "  --server-gateway   gateway of static network(example: 192.168.0.1)"
    log "  --server-dns       dns(example: 192.168.0.1)"
}

function check_depends() {
    local common_commands=(awk cat cp mkdir mv grep rm tee wget tar mount python make cc)
    local mac_commands=(route hdiutil ifconfig)
    local linux_commands=(ip)
    local not_exist_commands=()

    log_warn "checking depends"
    for c in ${common_commands[@]}; do
        if [ "$c" == "python" ]; then
            has_command $c
            if [ $? -ne 0 ]; then
                c="python3"
            fi
        fi
        has_command $c
        if [ $? -ne 0 ]; then
            not_exist_commands[${#not_exist_commands[@]}]=$c
        fi
    done
    is_darwin
    if [ $? -eq 0 ]; then
        for c in ${mac_commands[@]}; do
            has_command $c
            if [ $? -ne 0 ]; then
                not_exist_commands[${#not_exist_commands[@]}]=$c
            fi
        done
    else
        is_linux
        if [ $? -eq 0 ]; then
            for c in ${linux_commands[@]}; do
                has_command $c
                if [ $? -ne 0 ]; then
                    not_exist_commands[${#not_exist_commands[@]}]=$c
                fi
            done
        fi
    fi

    if [ ${#not_exist_commands[@]} -gt 0 ]; then
        log_error "commands are not exist: ${not_exist_commands[@]}"
        return 1
    fi

    log_info "depends ok"
    return 0
}

function prepare_dist_dir() {
    #|--dist
    #   |--services
    #   |--tftproot
    #   |--httproot
    #   |--download
    #      |--tmp
    local dist_dir=$1/dist

    mkdir -p $dist_dir/services
    rm -rf $dist_dir/services/*

    mkdir -p $dist_dir/tftproot
    rm -rf $dist_dir/tftproot/*

    mkdir -p $dist_dir/httproot
    rm -rf $dist_dir/httproot/*

    mkdir -p $dist_dir/download/tmp
    rm -rf $dist_dir/download/tmp/syslinux*
}

function install_bootloader() {
    local ip=$1
    local http_port=$2
    local download_file="download/syslinux-6.04-pre1.tar.xz"
    local syslinux_dir_prefix="syslinux-6.04-pre1"

    log_info "installing bootloader"
    log_info "  downloading syslinux"
    syslinux_url="https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/Testing/6.04/syslinux-6.04-pre1.tar.xz"
    retry 3 download $syslinux_url $download_file
    if [ $? -ne 0 ]; then
        log_error "  download syslinux error"
        return 1
    fi

    log_info "  extracting syslinux"
    extract_from_tar $download_file $syslinux_dir_prefix/bios/core/lpxelinux.0 $syslinux_dir_prefix/bios/com32/elflink/ldlinux/ldlinux.c32
    extract_from_tar $download_file $syslinux_dir_prefix/efi64/efi/syslinux.efi $syslinux_dir_prefix/efi64/com32/elflink/ldlinux/ldlinux.e64
    extract_from_tar $download_file $syslinux_dir_prefix/efi32/efi/syslinux.efi $syslinux_dir_prefix/efi32/com32/elflink/ldlinux/ldlinux.e32
    if [ $? -ne 0 ]; then
        log_error "  extract syslinux error"
        return 1
    fi

    log_info "  installing syslinux"
    mv -f $syslinux_dir_prefix download/tmp
    mv -f download/tmp/$syslinux_dir_prefix/bios/core/lpxelinux.0 tftproot
    mv -f download/tmp/$syslinux_dir_prefix/bios/com32/elflink/ldlinux/ldlinux.c32 tftproot
    mkdir -p tftproot/efi64
    mv -f download/tmp/$syslinux_dir_prefix/efi64/efi/syslinux.efi tftproot/efi64/syslinux.efi
    mv -f download/tmp/$syslinux_dir_prefix/efi64/com32/elflink/ldlinux/ldlinux.e64 tftproot/efi64
    mkdir -p tftproot/efi32
    mv -f download/tmp/$syslinux_dir_prefix/efi32/efi/syslinux.efi tftproot/efi32/syslinux.efi
    mv -f download/tmp/$syslinux_dir_prefix/efi32/com32/elflink/ldlinux/ldlinux.e32 tftproot/efi32

    log_info "  configuring syslinux"
    mkdir -p tftproot/pxelinux.cfg/
    cat <<EOF | tee tftproot/pxelinux.cfg/default
DEFAULT install
LABEL install
  KERNEL http://$ip:$http_port/casper/vmlinuz
  INITRD http://$ip:$http_port/casper/initrd
  APPEND root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://$ip:$http_port/ubuntu-22.04.1-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://$ip:$http_port/cloud-init/
EOF
    mkdir -p tftproot/efi64/pxelinux.cfg/
    cp tftproot/pxelinux.cfg/default tftproot/efi64/pxelinux.cfg/
    mkdir -p tftproot/efi32/pxelinux.cfg/
    cp tftproot/pxelinux.cfg/default tftproot/efi32/pxelinux.cfg/

    log_info "bootloader done"
    return 0
}

function install_dhcp_and_tftp() {
    local work_dir=$1
    local netmask=$2
    local download_file="download/dnsmasq-2.86.tar.xz"

    log_info "installing dhcp and tftp"
    if [ ! -d download/tmp/dnsmasq-2.86 ]; then
        log_info "  downloading dnsmasq"
        dnsmasq_url="https://thekelleys.org.uk/dnsmasq/dnsmasq-2.86.tar.xz"
        retry 3 download $dnsmasq_url $download_file
        if [ $? -ne 0 ]; then
            log_error "  download dnsmasq error"
            return 1
        fi

        log_info "  extracting dnsmasq"
        extract_from_tar $download_file
        if [ $? -ne 0 ]; then
            log_error "  extract dnsmasq error"
            return 1
        fi

        mv -f dnsmasq-2.86 download/tmp/
    fi

    log_info "  compiling dnsmasq"
    make -C download/tmp/dnsmasq-2.86
    if [ $? -ne 0 ]; then
        log_error "  compile dnsmasq error"
        return 1
    fi

    log_info "  installing dnsmasq"
    cp download/tmp/dnsmasq-2.86/src/dnsmasq services

    log_info "  configuring dnsmasq"
    cat <<EOF | tee services/dnsmasq.conf
port=0
log-dhcp
dhcp-range=$netmask,proxy
enable-tftp
tftp-root="$work_dir/dist/tftproot"
pxe-service=X86PC,"Boot x86 BIOS",lpxelinux.0
pxe-service=X86-64_EFI,"PXELINUX (EFI 64)",efi64/syslinux.efi
pxe-service=IA64_EFI,"PXELINUX (EFI 64)",efi64/syslinux.efi
pxe-service=IA32_EFI,"PXELINUX (EFI 32)",efi32/syslinux.efi
dhcp-leasefile=$work_dir/dist/services/dhcpd.conf.leases
EOF

    log_info "dhcp and tftp done"
    return 0
}

function install_http() {
    local server_address=$1
    local server_gateway=$2
    local server_dns=$3
    local rsa_public="$HOME/.ssh/id_rsa.pub"
    local download_file="download/ubuntu-22.04.1-live-server-amd64.iso"
    local temp

    log_info "installing http"
    log_info "  downloading ubuntu live iso"
    ubuntu_live_iso_url="https://releases.ubuntu.com/22.04/ubuntu-22.04.1-live-server-amd64.iso"
    retry 3 download $ubuntu_live_iso_url $download_file
    if [ $? -ne 0 ]; then
        log_error "  download ubuntu live iso error"
        return 1
    fi

    log_info "  extracting ubuntu live iso"
    iso_extract $download_file casper/vmlinuz casper/initrd
    if [ $? -ne 0 ]; then
        log_error "  extract vmlinuz and initrd error"
        return 1
    fi

    log_info "  install ubuntu live iso"
    mv -f casper httproot
    cp -f $download_file httproot/

    log_info "  configuring cloud-init"
    mkdir -p httproot/cloud-init/
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
    if [ -z $server_address ]; then
        server_address=$(get_input "input server address(CIDR format-192.168.0.6/24):")
    else
            log_info "    configuring cloud-init: address is $server_address"
    fi
    if [ -z $server_gateway ]; then
        server_gateway=$(get_default_gateway)
        if [ -z $server_gateway ]; then
            server_gateway=$(get_input "input server gateway:")
        else
            log_info "    configuring cloud-init: gateway is $server_gateway"
        fi
    fi
    if [ -z $server_dns ]; then
        server_dns=$(get_default_dns)
        if [ -z $server_dns ]; then
            server_dns=$(get_input "input server dns:")
        else
            log_info "    configuring cloud-init: dns is $server_dns"
        fi
    fi
    touch httproot/cloud-init/meta-data
    cat <<EOF | tee httproot/cloud-init/user-data
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: netboot-server
    username: ubuntu
    password: '\$6\$exDY1mhS4KUYCE/2\$zmn9ToZwTKLhCw.b4/b.ZRTIZM30JZ4QrOQ2aOXJ8yk96xpcCof0kxKwuX1kqLG/ygbJ1f8wxED22bTL4F46P0'
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - $(cat $rsa_public)
  packages:
    [dnsmasq, targetcli-fb, nginx]
  network:
    version: 2
    ethernets:
      eth0:
        match:
          name: e*
        addresses:
          - $server_address
        gateway4: $server_gateway
        nameservers:
          addresses:
            - $server_dns
  late-commands:
    - |
      cat <<EOF | sudo tee /target/etc/sudoers.d/010_ubuntu-nopasswd
      ubuntu ALL=(ALL) NOPASSWD:ALL
      EOF
    - curtin in-target --target /target chmod 440 /etc/sudoers.d/010_ubuntu-nopasswd
    - curtin in-target --target /target -- update-alternatives --set iptables /usr/sbin/iptables-legacy
    - curtin in-target --target /target -- update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
EOF

    log_info "http done"
    return 0
}

function run_dhcp_and_tftp() {
    local SUDO=sudo
    [ "$(id -u)" = "0" ] && SUDO=

    # fix bug: can't input password when process runs in background
    $SUDO cat /dev/null
    process_new $SUDO services/dnsmasq -d -C services/dnsmasq.conf 1>&2 2>services/dnsmasq.log
}

function run_http() {
    local http_port=$1

    cd httproot
    has_command python3
    if [ $? -eq 0 ]; then
        process_new python3 -m http.server $http_port
    else
        process_new python -m SimpleHTTPServer $http_port
    fi
    cd ..
}

function main() {
    local server_address
    local server_gateway
    local server_dns
    local work_dir="."

    ARGS=$(getopt -l "server-address:,server-gateway:,server-dns:,help" -a -o "h" -- "$@")
    while [ ! -z "$1" ]; do
        case "$1" in
        -h | --help)
            usage
            return 0
            ;;
        --server-address)
            server_address=$2
            shift
            ;;
        --server-gateway)
            server_gateway=$2
            shift
            ;;
        --server-dns)
            server_dns=$2
            shift
            ;;
        *) break ;;
        esac
        shift
    done

    check_depends
    if [ $? -ne 0 ]; then
        return 1
    fi

    work_dir=$(cd $(dirname $0) && pwd)
    prepare_dist_dir $work_dir
    cd $work_dir/dist

    log_info "start installing..."
    install_bootloader $(get_default_ip) 12345
    if [ $? -ne 0 ]; then
        return 1
    fi
    install_dhcp_and_tftp $work_dir $(get_default_broadcast)
    if [ $? -ne 0 ]; then
        return 1
    fi
    install_http $server_address $server_gateway $server_dns
    if [ $? -ne 0 ]; then
        return 1
    fi

    log_info "start running..."
    run_dhcp_and_tftp
    run_http 12345

    while true; do
        sleep 1
    done
    return 0
}

function cleanup() {
    process_kill_all_with_sudo
    process_wait_all
    exit 0
}

function handle_sigterm() {
    log_warn "Received SIGTERM"
    cleanup
}

function handle_sigint() {
    log_warn "Received SIGINT"
    cleanup
}

if [ -n "$BASH_SOURCE" -a "$BASH_SOURCE" == "$0" ]; then
    trap handle_sigterm SIGTERM
    trap handle_sigint SIGINT

    main $@
fi
