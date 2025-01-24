# SUSE"s openQA tests
#
# Copyright 2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Package: podman x11-container
# Summary: install and verify x11 container.
# Maintainer: Grace Wang <grace.wang@suse.com>

use base 'consoletest';
use warnings;
use strict;
use testapi;
use lockapi;
use mmapi;
use microos "microos_login";
use utils qw(set_hostname permit_root_ssh);
use transactional qw(trup_call check_reboot_changes);
use mm_network 'setup_static_mm_network';


# MM network check: try to ping the gateway, the client and the internet
sub ensure_client_reachable {
    assert_script_run('ping -c 1 10.0.2.2');
    assert_script_run('ping -c 1 10.0.2.102');
    # assert_script_run('curl conncheck.opensuse.org');
}

sub x11_preparation {
    # create volume
    assert_script_run("podman volume create xauthority");
    assert_script_run("podman volume create xsocket");
    assert_script_run("podman volume create pasocket");
    # create a pod
    assert_script_run("podman pod create --name wallboard-pod");
}

sub run {
    my ($self) = @_;

    select_console 'root-console';
    set_hostname(get_var('HOSTNAME') // 'server');
    setup_static_mm_network('10.0.2.101/24');
    ensure_client_reachable();

    # Permit ssh login as root
    assert_script_run("echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf");
    assert_script_run("systemctl restart sshd");


    # preparations
    x11_preparation();
    record_info("SERVER DEBUG", "pulling x11 container");

    # start container
    my $containerpath = 'registry.opensuse.org/home/atgracey/wallboardos/15.5/x11:notaskbar';
    assert_script_run("podman pull $containerpath", 14000);
    assert_script_run("podman run --privileged -d --pod wallboard-pod -e XAUTHORITY=/home/user/xauthority/.xauth -v xauthority:/home/user/xauthority:rw -v xsocket:/tmp/.X11-unix:rw -v /run/udev/data:/run/udev/data:rw --name x11-init-container --security-opt=no-new-privileges $containerpath");

    assert_screen "icewm_wallboard";

    # Notify that the server is ready
    mutex_create("x11_container_ready");

    wait_for_children();
    assert_screen "linux-login-microos";
    enter_cmd "root";
    assert_screen "password-prompt";
    type_password();
    send_key "ret";
    wait_still_screen 1;
}

1;

