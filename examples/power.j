#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * power example: power a VM on, or shut its guest down, by name.
 *
 * Writes: it changes the VM's power state. Run with:
 *   VC_HOST=vcenter.example.com VC_USER=administrator@vsphere.local VC_PASSWORD=... \
 *       VC_VM=web01 VC_ACTION=on jennifer run examples/power.j
 * VC_ACTION is `on` or `shutdown`.
 */

use io;
use os;

import "../src/vmware.j" as vmware;

def host as string init os.getEnv("VC_HOST");
def name as string init os.getEnv("VC_VM");
def action as string init os.getEnv("VC_ACTION");
if ($host == "" or $name == "" or ($action != "on" and $action != "shutdown")) {
    io.printf("set VC_HOST, VC_USER, VC_PASSWORD, VC_VM and VC_ACTION (on or shutdown)\n");
    exit 1;
}

def c as vmware.Client init vmware.client($host);
if (os.getEnv("VC_INSECURE") == "1") {
    $c = vmware.withInsecure($c);
}
$c = vmware.login($c, os.getEnv("VC_USER"), os.getEnv("VC_PASSWORD"));

def vm as vmware.VmSummary init vmware.vmByName($c, $name);
io.printf("%s (%s) is %s\n", $vm.name, $vm.vm, $vm.powerState);

try {
    if ($action == "on") {
        vmware.powerOn($c, $vm.vm);
    } else {
        vmware.shutdownGuest($c, $vm.vm);
    }
    io.printf("now %s\n", vmware.powerState($c, $vm.vm));
    def id as vmware.GuestIdentity init vmware.guestIdentity($c, $vm.vm);
    io.printf("guest %s at %s\n", $id.hostName, $id.ipAddress);
} catch (e) {
    io.printf("%s\n", $e.message);
}

vmware.logout($c);
