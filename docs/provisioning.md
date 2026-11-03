<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Provisioning

A new VM usually comes from a template: clone it, give the copy its own name
and address, power it on.

## Cloning as a task

`vmware.cloneVm` holds the connection until the copy is done. `vmware.cloneVmTask`
returns a task id at once; `vmware.waitTask` follows it, and the finished
task's `result` is the new VM's id.

```jennifer
import "@deckyard/vmware/" as vmware;

def p as vmware.Placement;
$p.folder = "group-v4";
$p.datastore = "datastore-15";
def id as string init vmware.cloneVmTask($c, vmware.vmByName($c, "tpl-ubuntu-24").vm, "web08", $p, false);
def t as vmware.Task init vmware.waitTask($c, $id, 1800000);
if ($t.status != "SUCCEEDED") {
    io.printf("clone failed: %s\n", $t.error);
    exit 1;
}
def vm as string init $t.result;
```

`waitTask` asks once a second (`vmware.withPollInterval` changes it) and
throws when its timeout runs out; a failed task does not throw, so check
`status`. A network failure or a 5xx answer during the wait is retried, up to
`MAX_POLL_FAILURES` (5) in a row; a 4xx answer, such as an ended session,
ends the wait at once. `waitGuestProcess` behaves the same. `vmware.startTask` starts any other operation the API reference
marks as a task, by adding `vmw-task=true`.

## Guest customization

Customization gives a copy its own identity: host name, domain, time zone,
DNS and the address of its first NIC. It needs VMware Tools in the template
and is applied at the next power-on, so customize the VM while it is off.

```jennifer
def lc as vmware.LinuxCustomization;
$lc.hostName = "web08";
$lc.domain = "lab.example";
$lc.ipAddress = "10.0.0.8";
$lc.prefix = 24;
$lc.gateway = "10.0.0.1";
$lc.dnsServers = ["10.0.0.1"];
$lc.dnsSuffixes = ["lab.example"];
vmware.customizeLinux($c, $vm, $lc);
vmware.powerOn($c, $vm);
```

Leave `ipAddress` empty for DHCP. For a setting `LinuxCustomization` lacks,
build the spec with `vmware.linuxSpec`, change it with `json.set` and apply it
with `vmware.customizeWith`. A specification stored in vCenter (listed by
`vmware.customizationSpecs`, and the only way for Windows guests here) is
applied by name with `vmware.customize`.
