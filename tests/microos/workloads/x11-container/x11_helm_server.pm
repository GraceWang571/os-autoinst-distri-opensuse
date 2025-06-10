# SUSE"s openQA tests
#
# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Deploy X11, pulseaudio, firefox kiosk
#          with Kubernetes Using Helm
# Maintainer: Grace Wang <grace.wang@suse.com>

use base 'consoletest';
use warnings;
use strict;
use testapi;
use lockapi;
use mmapi;
use utils;
use mm_network 'setup_static_mm_network';
use containers::k8s;
# use containers::helm;
use transactional;

# MM network check: try to ping the gateway, the client and the internet
sub ensure_client_reachable {
    assert_script_run('ping -c 1 10.0.2.2');
    assert_script_run('ping -c 1 10.0.2.102');
    assert_script_run('curl conncheck.opensuse.org');
}

sub run {
    my ($self) = @_;
    my $release_name = "kiosk";
    my $namespace = "kiosk";
    # my $helm_chart = "";
    my $helm_values = "kiosk_values.yaml";
    my $kiosk_helm_repo = "oci://registry.suse.de/suse/sle-15-sp6/update/bci/helmcharts/suse/kiosk/kiosk-chart";

    select_console 'root-console';
    set_hostname(get_var('HOSTNAME') // 'server');
    setup_static_mm_network('10.0.2.101/24');
    ensure_client_reachable();

    # Permit ssh login as root
    assert_script_run("echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf");
    assert_script_run("systemctl restart sshd");

    # Install the package ca-certificates-suse and git
    my $host_version = get_var("HOST_VERSION") ? 'HOST_VERSION' : 'VERSION';
    my $distversion = 'SLE_' . get_required_var($host_version) =~ s/-SP/_SP/r;
    enter_trup_shell;
    zypper_call("ar --refresh http://download.suse.de/ibs/SUSE:/CA/$distversion/SUSE:CA.repo");
    zypper_call("ar --refresh https://download.opensuse.org/distribution/leap-micro/6.1/product/repo/openSUSE-Leap-Micro-6.1-x86_64/ leap-micro-6.1");
    transactional::trup_call('--continue pkg install ca-certificates-suse git');
    exit_trup_shell;
    check_reboot_changes;

    # Install k3s and helm
    install_k3s();

    assert_script_run("curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3");
    assert_script_run("chmod 700 get_helm.sh");
    assert_script_run("./get_helm.sh");
    record_info('helm', script_output("helm version"));

    # deploy using Helm
    assert_script_run("curl " . data_url("x11/helm_chart/$helm_values") . " -o $helm_values", 60);
    assert_script_run("helm install $release_name -f $helm_values -n $namespace --create-namespace --generate-name $release_name", timeout => 100);

    # verify the firefox kiosk container started
    assert_screen("firefox_kiosk", 300);
    assert_and_click "firefox_play_audio";

    # Notify that the server is ready
    mutex_create("x11_helm_server_ready");

    wait_for_children();
}

1;

