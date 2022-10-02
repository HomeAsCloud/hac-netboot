download_outfile="outfile"

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    load 'test_helper/bats-file/load'

    # get the containing directory of this file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
    # as those will point to the bats executable's location or the preprocessed file respectively
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
    # make executables in ../ visible to PATH
    PATH="$DIR/../:$PATH"

    load ../device_module.sh
    load ../img.sh
    load ../ip.sh
    load ../iso.sh
    load ../process.sh
    load ../util.sh
}

teardown() {
    rm -f $download_outfile
}

@test "retry" {
    errorurl="http://localhost:9999"
    run retry 3 download $errorurl $download_outfile
    assert_output --partial "retry 1: download $errorurl outfile"
    assert_output --partial "retry 2: download $errorurl outfile"
    assert_output --partial "retry 3: download $errorurl outfile"
}

@test "download" {
    run download http://www.baidu.com $download_outfile
    assert_success
    errorurl="http://localhost:9999"
    run download $errorurl $download_outfile
    assert_failure
}

@test "extract_from_tar" {
    syslinux_dir_prefix="syslinux-6.04-pre1"
    if [ ! -f syslinux-6.04-pre1.tar.xz ]; then
        skip 'syslinux-6.04-pre1.tar.xz exists?'
    fi
    rm -rf $syslinux_dir_prefix
    run extract_from_tar $syslinux_dir_prefix.tar.xz $syslinux_dir_prefix/bios/core/pxelinux.0 $syslinux_dir_prefix/bios/com32/elflink/ldlinux/ldlinux.c32
    assert_success
    assert_exists $syslinux_dir_prefix/bios/core/pxelinux.0
    assert_exists $syslinux_dir_prefix/bios/com32/elflink/ldlinux/ldlinux.c32
    rm -rf $syslinux_dir_prefix
}

@test "extract_from_not_exist_tar" {
    run extract_from_tar not_exist_tarfile syslinux-6.03/bios/core/pxelinux.0 syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32
    assert_failure
    assert_not_exists syslinux-6.03/bios/core/pxelinux.0
    assert_not_exists syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32
}

@test "iso_extract" {
    if [ ! -f ubuntu-22.04.1-live-server-amd64.iso ]; then
        skip 'ubuntu-22.04.1-live-server-amd64.iso exists?'
    fi
    rm -rf casper
    run iso_extract ubuntu-22.04.1-live-server-amd64.iso casper/vmlinuz casper/initrd
    assert_success
    assert_exists casper/vmlinuz
    assert_exists casper/initrd
    rm -rf casper
}

@test "iso_extract_not_exist" {
    run iso_extract not_exist.iso casper/vmlinuz casper/initrd
    assert_failure
    assert_not_exists casper/vmlinuz
    assert_not_exists casper/initrd
}

@test "process_new_and_kill" {
    #run process_new "tail -f /dev/null"
    #ret=$(process_new "tail -f /dev/null")
    #avoid hang bats
    process_new "tail -f /dev/null"
    pid1=$(process_get_last_id)
    process_new "tail -f /dev/null"
    pid2=$(process_get_last_id)
    assert_not_equal $pid1 $pid2

    run process_kill_all
    assert_success
}

@test "process_kill_null" {
    run process_kill_all
    assert_success
}

@test "has_command" {
    run has_command cd
    assert_success
    run has_command cd_not_exist
    assert_failure
}

@test "get default ip and broadcast" {
    if [[ $OSTYPE =~ darwin* ]]; then
        ip=$(ifconfig $(route -n get default | grep interface | awk '{print $2}') | grep 'inet ' | awk '{print $2}')
        assert_equal $ip $(get_default_ip)
        broadcast=$(ifconfig $(route -n get default | grep interface | awk '{print $2}') | grep 'inet ' | awk '{print $6}')
        assert_equal $broadcast $(get_default_broadcast)
    fi
    if [[ $OSTYPE =~ linux* ]]; then
        ip=$(ip address show $(ip route | grep default | awk '{print $5}') | grep 'inet ' | awk '{print $2}' | awk -F '/' '{print $1}')
        assert_equal $ip $(get_default_ip)
        broadcast=$(ip address show $(ip route | grep default | awk '{print $5}') | grep 'inet ' | awk -F 'brd' '{print $2}' | awk '{print $1}')
        assert_equal $broadcast $(get_default_broadcast)
    fi
}

@test "get default gateway and dns" {
    if [[ $OSTYPE =~ darwin* ]]; then
        gateway=$(route -n get default | grep gateway | awk '{print $2}')
        assert_equal $gateway $(get_default_gateway)
        dns=$(scutil --dns | grep nameserver | tail -n 1 | awk '{print $3}')
        assert_equal $dns $(get_default_dns)
    fi
    if [[ $OSTYPE =~ linux* ]]; then
        gateway=$(ip route | grep default | awk '{print $3}')
        assert_equal $gateway $(get_default_gateway)
        dns=$(resolvectl | grep 'Current DNS Server' | awk -F ':' '{print $2}')
        assert_equal $dns $(get_default_dns)
    fi
}

@test "img mount" {
    img_file='2022-09-06-raspios-bullseye-arm64-lite.img'
    run is_linux
    if [ $status -ne 0 ]; then
        skip 'need linux'
    fi
    if [ "$(id -u)" != "0" ]; then
        skip 'need root privilege'
    fi
    if [ ! -f $img_file ]; then
        skip "$img_file exists?"
    fi
    rm -rf boot
    rm -rf root
    mkdir boot
    mkdir root
    cur_device=$(get_current_device)
    run img_mount $cur_device $img_file boot root
    assert_success
    assert_exists boot/start4.elf
    assert_exists root/etc/
    run img_umount $cur_device boot root

    run img_mount $cur_device $img_file boot root error
    assert_failure
    run img_umount $cur_device boot root

    rm -rf boot
    rm -rf root
}

@test "device_module" {
    module_dir="device_module_temp"
    rm -rf $module_dir
    mkdir $module_dir
    modules="a b"
    for m in $modules; do
        cat <<EOF | tee $module_dir/$m.sh 2>&1 1>/dev/null
#!/bin/bash
device_probe_$m() { echo \$1 | grep -E -o "^$m:$m[0-9]*" | awk -F ':' '{print \$2}'; }
device_check_id_$m() { echo \$1 | grep -E -o "^$m[0-9]*$"; return \$?; }
device_add_$m() { return 0; }
EOF
    done

    device_module_init $module_dir

    run device_probe "a:a123"
    assert_output "a123"
    run device_probe "b:b321"
    assert_output "b321"

    run device_add "a123"
    assert_success
    run device_add "b321"
    assert_success
    run device_add "c999"
    assert_failure

    run device_check_id "a123"
    assert_success
    run device_check_id "b321"
    assert_success
    run device_check_id "c999"
    assert_failure

    rm -rf $module_dir
}

@test "device_module pc" {
    source ../device_module/pc.sh
    run device_probe_pc "dnsmasq-tftp[954]: file /var/hac/tftproot/efi64/pxelinux.cfg/01-00-0c-29-4f-62-c7 not found"
    assert_output "01-00-0c-29-4f-62-c7"
    run device_probe_pc "errorprefix/01-00-0c-29-4f-62-c7 not found"
    assert_output ""
    run device_probe_pc "dnsmasq-tftp pxelinux.cfg/01-00-0c-29-4f-62-c7 errorsuffix"
    assert_output ""
}

@test "device_module raspberrypi" {
    source ../device_module/raspberrypi.sh
    run device_probe_raspberrypi "dnsmasq-tftp[1628]: file /var/hac/tftproot/7092246e/start4.elf not found"
    assert_output "7092246e"
    run device_probe_raspberrypi "errorprefix/7092246e/start4.elf not found"
    assert_output ""
    run device_probe_raspberrypi "dnsmasq-tftp /7092246e/start4.elf errorsuffix"
    assert_output ""
}
