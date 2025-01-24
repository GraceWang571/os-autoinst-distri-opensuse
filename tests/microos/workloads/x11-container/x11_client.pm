# SUSE"s openQA tests
#
# Copyright 2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Package: podman x11-container
# Summary: install and verify x11 container.
# Maintainer: Grace Wang <grace.wang@suse.com>

# use base 'consoletest';
use warnings;
use strict;
use testapi;
use lockapi;
use base 'x11test';
use mmapi;
use mm_tests;
use x11utils 'turn_off_gnome_screensaver';

# MM network check: try to ping the gateway, and the server
sub ensure_server_reachable {
    assert_script_run('ping -c 1 10.0.2.2');
    assert_script_run('ping -c 1 10.0.2.101');
}

sub run {

    my $self = shift;

    # Setup static NETWORK
    $self->configure_static_ip_nm('10.0.2.102/24');

    x11_start_program('xterm');
    turn_off_gnome_screensaver;

    mutex_wait("x11_container_ready");

    ensure_server_reachable();

    # ssh login to the x11 server
    type_string("ssh root\@10.0.2.101");
    send_key "ret";
    assert_screen 'ssh-login', 60;
    enter_cmd "yes";
    assert_screen 'password-prompt', 60;
    type_password();
    send_key "ret";
    assert_screen 'ssh-login-ok';

    # stop container
    type_string("podman stop x11-init-container");
    send_key "ret";
    wait_screen_change { send_key 'ret' };
    wait_still_screen 3;
    enter_cmd "reboot";
    send_key "alt-f4";
    assert_screen 'generic-desktop';
}

1;

