# SUSE"s openQA tests
#
# Copyright 2024-2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Runs X11 Podman container server test.
#          Simplified the workflow in a single module
#          Include extended test cases (wallpaper, keys, benchmark)
# Maintainer: Grace Wang <grace.wang@suse.com>

use Mojo::Base 'x11test';
use testapi;
use utils;
use containers::common;
use mm_network 'setup_static_mm_network';

sub x11_preparation {

    # Download custom wallboard
    assert_script_run("curl -o /root/wallpaper.png https://hackweek.opensuse.org/img/HW25/SUSE_Hackweek25_Wallpaper_widescreen.png");

    # Create the Xmodmap to test remap 'a'>'b' and 'b'>'a'
    my $custom_modmap = "/root/kiosk.Xmodmap";
    assert_script_run("touch $custom_modmap");
    assert_script_run("echo keycode  38 = b B >> $custom_modmap");
    assert_script_run("echo keycode  56 = a A >> $custom_modmap");

    # Create volume
    assert_script_run("podman volume create xauthority");
    assert_script_run("podman volume create xsocket");
    assert_script_run("podman volume create pasocket");

    # Create a pod
    assert_script_run("podman pod create --name wallboard-pod");
}

sub run {
    my ($self) = @_;

    $self->select_serial_terminal;

    # Preparations
    setup_static_mm_network('10.0.2.101/24');
    x11_preparation();

    # Login to graphical tty before starting
    select_console 'root-console';

    # Pull the X11 image
    $self->select_serial_terminal;
    my $containerpath = get_var('CONTAINER_IMAGE_TO_TEST', 'registry.suse.de/suse/sle-15-sp6/update/cr/totest/images/suse/kiosk/xorg:notaskbar');
    assert_script_run("podman pull $containerpath --tls-verify=false", 300);

    # Pulseaudio image url and Firefox kiosk are joined together by a space
    # Split the string by space
    my ($pacontainerpath, $ffcontainerpath) = split(/\s+/, get_var("CONTAINER_IMAGE_TO_TEST", 'registry.suse.de/suse/sle-15-sp6/update/cr/totest/images/suse/kiosk/pulseaudio:17 registry.suse.de/suse/sle-15-sp6/update/cr/totest/images/suse/kiosk/firefox-esr:esr'));
    # Pull the Pulseaudio and Firefox kiosk image
    assert_script_run("podman pull $pacontainerpath --tls-verify=false", 300);
    assert_script_run("podman pull $ffcontainerpath --tls-verify=false", 300);

    # Start the X11 container
    assert_script_run("podman run --privileged -d --pod wallboard-pod -e XAUTHORITY=/home/user/xauthority/.xauth -v xauthority:/home/user/xauthority:rw -v xsocket:/tmp/.X11-unix:rw -v /run/udev/data:/run/udev/data:rw --name x11-init-container --security-opt=no-new-privileges  -v /root/wallpaper.png:/usr/share/wallpapers/SLEdefault/contents/images/1920x1080.png:ro -v /root/kiosk.Xmodmap:/root/.Xmodmap:ro $containerpath");

    # Verify the x11 server container started and custom wallboard worked
    select_console 'root-console';
    assert_screen "icewm_custom_wallboard";
    send_key "super";
    assert_and_click "menu-appear";
    enter_cmd "aaabbb";
    assert_screen "remap_key_success";
    send_key "alt-f4";

    $self->select_serial_terminal;
    # Start pulseaudio container
    my $opts = "-e DISPLAY=:0 -e XAUTHORITY=/home/user/xauthority/.xauth -e PULSE_SERVER=/var/run/pulse/native -v xauthority:/home/user/xauthority:rw -v pasocket:/var/run/pulse/ -v xsocket:/tmp/.X11-unix:rw";
    assert_script_run("podman run -d --pod wallboard-pod $opts -v /run/udev/data:/run/udev/data:rw --name pulseaudio-container --privileged $pacontainerpath bash -c 'chown root:audio /dev/snd/*; /usr/bin/pulseaudio -vvv --log-target=stderr'");

    # Start firefox container
    # URL https://freesound.org/people/kevp888/sounds/796468/ can be used for testing
    # Since it doesn't have ads and require login before playing audio
    assert_script_run("podman run -d --pod wallboard-pod -e URL=https://freesound.org/people/kevp888/sounds/796468/ $opts --user 1000 --name wallboard-container --security-opt=no-new-privileges $ffcontainerpath");

    select_console 'root-console';
    # Verify the firefox kiosk container started
    assert_screen("firefox_kiosk", 300);
    assert_and_click "firefox_play_audio";

    $self->select_serial_terminal;
    # Check the audio can be played fine from the code leve
    assert_script_run("podman exec pulseaudio-container ps aux | grep pulseaudio");
    assert_script_run("podman exec pulseaudio-container pactl list sink-inputs");

    # Stop the running containers
    assert_script_run("podman stop wallboard-container");
    assert_script_run("podman stop pulseaudio-container");
    assert_script_run("podman stop x11-init-container");

    sleep 60;
    select_console 'root-console';
}

sub post_run_hook { }

sub post_fail_hook {
    my ($self) = @_;
    # Gather logs for debugging on failure
    if (script_run("podman ps -a | grep wallboard-container") == 0) {
        script_run "podman logs wallboard-container";
    }
    $self->SUPER::post_fail_hook;
}

1;
