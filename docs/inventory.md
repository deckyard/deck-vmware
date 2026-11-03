<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Inventory and power

## VMs

`vmware.vms` lists VMs with their power state, CPU count and memory. A
`VmFilter` narrows the list: every field is a list of values, an empty list
does not filter, and the zero filter selects every VM.

```jennifer
import "@deckyard/vmware/" as vmware;

def f as vmware.VmFilter;
$f.powerStates = [vmware.POWERED_ON];
$f.clusters = ["domain-c8"];
for (def vm in vmware.vms($c, $f)) {
    io.printf("%s %s %d MiB\n", $vm.vm, $vm.name, $vm.memoryMiB);
}
```

vCenter refuses to list more than 4000 VMs at once
(`UNABLE_TO_ALLOCATE_RESOURCE`); filter by cluster, host or folder then.

`vmware.vmByName` finds the one VM with an exact name and throws when there
is none or more than one. `vmware.vm` returns everything about one VM as a
`json.Value`: hardware version, CPU, memory, disks, NICs, boot order.

```jennifer
def web as vmware.VmSummary init vmware.vmByName($c, "web01");
def detail as json.Value init vmware.vm($c, $web.vm);
io.printf("%d cores per socket\n", json.asInt($detail, "/cpu/cores_per_socket"));
```

## Power

| Function | What it does |
|---|---|
| `vmware.powerOn` | power on |
| `vmware.powerOff` | cut the power |
| `vmware.suspend` | suspend to disk |
| `vmware.reset` | press the reset button |
| `vmware.shutdownGuest` | ask the guest OS to shut down |
| `vmware.rebootGuest` | ask the guest OS to reboot |

The first four return when the VM has changed state. The two guest actions
need VMware Tools running in the guest and return as soon as the request is
delivered; poll `vmware.powerState` to see the VM go off.

A VM already in the requested state fails with `ALREADY_IN_DESIRED_STATE`.

## Creating, cloning and deleting

`vmware.createVm` makes an empty VM from a `VmSpec`, powered off, and returns
its id. Look the ids up with `vmware.folders`, `vmware.clusters`,
`vmware.datastores` and `vmware.networks`.

```jennifer
import "@deckyard/vmware/" as vmware;

def s as vmware.VmSpec;
$s.name = "web05";
$s.guestOs = "UBUNTU_64";
$s.placement.folder = "group-v4";
$s.placement.cluster = "domain-c8";
$s.placement.datastore = "datastore-15";
$s.cpuCount = 2;
$s.memoryMiB = 4096;
$s.diskGiB = 40;
$s.network = "network-17";
def id as string init vmware.createVm($c, $s);
```

`networkType` must match the network: `DISTRIBUTED_PORTGROUP` for a
distributed port group, as `vmware.networks` reports it. For a setting
`VmSpec` lacks, change the body first:

```jennifer
def body as json.Value init vmware.createSpec($s);
$body = json.set($body, "/boot", json.decode('{"type": "EFI"}'));
def id as string init vmware.createVmFrom($c, $body);
```

Most VMs come from a copy rather than from scratch. `vmware.cloneVm` copies a
VM; `vmware.deployTemplate` deploys a VM template stored in a content
library. Empty placement fields keep the source's.

```jennifer
def p as vmware.Placement;
$p.resourcePool = "resgroup-9";
$p.datastore = "datastore-15";
def web06 as string init vmware.cloneVm($c, "vm-42", "web06", $p, true);

def item as string init vmware.findLibraryItem($c, "ubuntu-24.04");
def web07 as string init vmware.deployTemplate($c, $item, "web07", $p, true);
```

`cloneVm` and `deployTemplate` answer only when the copy is done, which can
take minutes. Raise the idle timeout first, or the client gives up after 30 s
while vCenter carries on: `$c = vmware.withTimeout($c, 900000);`. Or clone
as a task with `vmware.cloneVmTask`; see [Provisioning](provisioning.md).

An OVF template in a library deploys through another endpoint,
`/api/vcenter/ovf/library-item/<id>?action=deploy`; call it with
`vmware.post`. Older vCenter releases lack the clone endpoint and answer 404.

`vmware.deleteVm` removes a VM and its disks. Power it off first.

## The guest

`vmware.guestIdentity` returns what VMware Tools reports: the guest OS, its
host name and primary IP address. Without Tools running it fails with
`SERVICE_UNAVAILABLE`.

```jennifer
def id as vmware.GuestIdentity init vmware.guestIdentity($c, "vm-42");
io.printf("%s (%s) at %s\n", $id.hostName, $id.fullName, $id.ipAddress);
```

## Hosts, clusters and the rest

`vmware.hosts`, `vmware.clusters` and `vmware.datastores` return typed
lists. Datacenters, networks, folders and resource pools come back as
`Item`s: id, name and, for networks and folders, the type.

```jennifer
for (def d in vmware.datastores($c)) {
    io.printf("%s: %d%% free\n", $d.name, $d.freeSpace * 100 // $d.capacity);
}
def vmFolders as list of vmware.Item init vmware.folders($c, "VIRTUAL_MACHINE");
```
