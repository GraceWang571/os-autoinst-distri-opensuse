# SUSE's openQA tests
#
# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: MozillaFirefox
# Summary: Case#1479153 Firefox: Smoke Test
# - Launch xterm, kill firefox, cleanup previous firefox configuration, launch
# firefox and handle popups
# - Exit firefox
# Maintainer: wnereiz <wnereiz@github>

use Mojo::Base 'x11test';
use testapi;
use x11utils;
use utils 'zypper_call';
use version_utils 'is_tumbleweed';

sub run {
    my ($self) = @_;

    ## some w3m files will be used later in firefox tests.
    ensure_installed 'w3m' if is_tumbleweed;
    x11_start_program(default_gui_terminal());
    become_root;
    enter_cmd("wget https://dist.nue.suse.com/ibs/SUSE:/CA/SLE_15_SP7/noarch/ca-certificates-suse-1.0-150700.8.1.noarch.rpm --no-check-certificate");
    enter_cmd("rpm -ivh ca-certificates-suse-1.0-150700.8.1.noarch.rpm");
    zypper_call("--gpg-auto-import-keys ar --enable --refresh https://download.suse.de/ibs/Devel:/Desktop:/Mozilla:/SLE-15:/next/SUSE_SLE-15-SP7/ mozilla-153");
    zypper_call("in -y --allow-vendor-change MozillaFirefox");
    enter_cmd("exit");
    enter_cmd("exit");

    $self->start_clean_firefox;

    my $filename = "firefox.pdf";
    save_print_file($filename);

    $self->exit_firefox_common;
    validate_script_output("file $filename", sub { m/PDF document/ });
    # Exit
    $self->exit_firefox;
}

sub test_flags {
    return {fatal => 1, milestone => 1};
}

1;
