# SUSE's openQA tests
#
# Copyright 2024-2025 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Test Firefox native GTK print dialog by forcing system dialog preference
# Maintainer: Grace Wang <grace.wang@suse.com>

use base "x11test";
use testapi;
use x11utils qw(close_gui_terminal default_gui_terminal);


sub run {
    my ($self) = @_;

    # Start Firefox
    $self->start_firefox_with_profile;

    # Open about:config to change print settings
    # We must do this because Ctrl+Shift+P conflicts with "New Private Window"
    $self->firefox_open_url('about:config');

    # Handle the "Accept the Risk and Continue" warning if it appears
    if (check_screen('firefox-config-warning', 3)) {
        send_key 'ret';
    }

    sleep 2;
    # Search for the preference
    type_string "print.prefer_system_dialog";

    # Toggle the setting to TRUE
    assert_and_click("toggle-prefer-system-dialog-true");

    # Open a content page to test printing
    $self->firefox_open_url('about:support');    # Using a built-in page ensures consistent content
    assert_screen 'firefox-content-loaded';    # Generic needle checking the page loaded

    # Trigger Print
    # Since we changed the pref, Ctrl+P now opens the Native GTK Dialog directly
    send_key "ctrl-p";

    # Verify the Native GTK Dialog appears
    assert_screen 'firefox-native-print-dialog';
    assert_and_click 'firefox-native-print-2-file';
    send_key 'ret';

    # Exit firefox
    $self->exit_firefox;

    # Verify output file
    x11_start_program(default_gui_terminal);
    assert_script_run "file mozilla.pdf";
    # Close gui terminal
    close_gui_terminal;
    wait_still_screen;

    x11_start_program("evince /home/$username/mozilla.pdf", target_match => "evince-mozilla-output-default");
    send_key "alt-f10";
    assert_screen "mozilla-native-print-output";
    send_key "alt-f4";

}

1;
