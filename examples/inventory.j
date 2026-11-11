#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * inventory example: list the hosts, datastores and VMs of a vCenter.
 *
 * Read-only. Run with:
 *   VC_HOST=vcenter.example.com VC_USER=administrator@vsphere.local VC_PASSWORD=... \
 *       jennifer run examples/inventory.j
 * VC_INSECURE=1 accepts a certificate from an untrusted CA.
 */

use io;
use os;

import "../src/vmware.j" as vmware;

def host as string init os.getEnv("VC_HOST");
if ($host == "" or os.getEnv("VC_USER") == "") {
    io.printf("set VC_HOST, VC_USER and VC_PASSWORD first\n");
    exit 1;
}

def c as vmware.Client init vmware.client($host);
if (os.getEnv("VC_INSECURE") == "1") {
    $c = vmware.withInsecure($c);
}
$c = vmware.login($c, os.getEnv("VC_USER"), os.getEnv("VC_PASSWORD"));

def v as vmware.Version init vmware.version($c);
io.printf("%s %s (build %s)\n\n", $v.product, $v.version, $v.build);

for (def h in vmware.hosts($c)) {
    io.printf("host %-10s %-24s %s\n", $h.host, $h.name, $h.connectionState);
}
def gib as int init 1073741824;
for (def d in vmware.datastores($c)) {
    io.printf(
        "datastore %-16s %-6s %d of %d GiB free\n",
        $d.name,
        $d.type,
        $d.freeSpace // $gib,
        $d.capacity // $gib);
}

io.printf("\n");
def all as vmware.VmFilter;
for (def vm in vmware.vms($c, $all)) {
    io.printf(
        "%-8s %-24s %-12s %d CPU %d MiB\n",
        $vm.vm,
        $vm.name,
        $vm.powerState,
        $vm.cpuCount,
        $vm.memoryMiB);
}

vmware.logout($c);
