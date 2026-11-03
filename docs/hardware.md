<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Hardware and tags

## CPU and memory

```jennifer
import "@deckyard/vmware/" as vmware;

vmware.setCpu($c, "vm-42", 4);
vmware.setMemory($c, "vm-42", 8192);
```

A powered-off VM takes any change. A running one needs CPU or memory hot add
enabled in its settings, and memory can then only grow.

## Disks

`vmware.disks` lists the virtual disks with their size and VMDK file;
`vmware.addDisk($c, $vm, 20)` adds an empty 20 GiB disk and returns its id;
`vmware.removeDisk` detaches one and leaves its VMDK on the datastore.

Growing an existing disk is not in the REST API; it needs the SOAP API.

## Network adapters

`vmware.nics` lists the adapters with their MAC address, network and state.
`vmware.addNic` adds a VMXNET3 adapter on a network that connects at
power-on; pass the network's type as `vmware.networks` reports it.
`vmware.connectNic` and `vmware.disconnectNic` plug a running VM's adapter
in and out; `vmware.removeNic` removes it.

```jennifer
def nic as string init vmware.addNic($c, "vm-42", "dvportgroup-21", "DISTRIBUTED_PORTGROUP");
```

## Tags

Tags belong to categories. A `SINGLE` category allows one of its tags per
object (an environment: `prod` or `test`), a `MULTIPLE` one several (owners).

```jennifer
def env as string init vmware.createCategory($c, "env", "SINGLE");
def prod as string init vmware.createTag($c, $env, "prod");
vmware.attachTag($c, $prod, "vm-42");

for (def vm in vmware.taggedVms($c, $prod)) {
    io.printf("%s\n", $vm);
}
```

`vmware.categories` and `vmware.tags` list them with names (one request per
entry); `vmware.vmTags` lists the tag ids on a VM. These functions tag VMs;
for hosts or datastores, post to `/api/cis/tagging/tag-association` with
another `object_id` type.
