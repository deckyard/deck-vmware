<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# vmware cheatsheet

Every export of `@deckyard/vmware`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/vmware/" as vmware;
```

Every function that sends a request throws `Error{kind: "vmware"}` when it
fails. A `vm` argument is a VM id such as `vm-42`.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"vmware"` | the `kind` of every error the deck throws |
| `MAX_POLL_FAILURES` | `5` | failed checks in a row after which the wait functions give up |
| `SESSION_HEADER` | `"vmware-api-session-id"` | the header that carries the session id |
| `POWERED_ON` | `"POWERED_ON"` | power state: running |
| `POWERED_OFF` | `"POWERED_OFF"` | power state: off |
| `SUSPENDED` | `"SUSPENDED"` | power state: suspended |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `url as string` | `https://host`, no trailing slash |
| `session as string` | session id from `login`; `""` for none |
| `tls as http.TlsOptions` | certificate checking |
| `timeoutMs as int` | idle timeout per request; 0 for the `http` default |
| `retries as int` | retries of a GET answered 429 or 5xx |
| `pollMs as int` | interval of `waitTask` and `waitGuestProcess` |

### `VmFilter`

| Field | Meaning |
|---|---|
| `vms as list of string` | VM ids |
| `names as list of string` | exact VM names |
| `powerStates as list of string` | `POWERED_ON`, `POWERED_OFF`, `SUSPENDED` |
| `hosts as list of string` | host ids |
| `clusters as list of string` | cluster ids |
| `datacenters as list of string` | datacenter ids |
| `folders as list of string` | folder ids |
| `resourcePools as list of string` | resource pool ids |

### `Placement`

| Field | Meaning |
|---|---|
| `folder as string` | VM folder id |
| `resourcePool as string` | resource pool id |
| `cluster as string` | cluster id |
| `host as string` | host id |
| `datastore as string` | datastore id |

### `VmSpec`

| Field | Meaning |
|---|---|
| `name as string` | VM name |
| `guestOs as string` | guest OS id, e.g. `UBUNTU_64` |
| `placement as Placement` | where it goes |
| `cpuCount as int` | virtual CPUs; 0 for the default |
| `memoryMiB as int` | memory in MiB; 0 for the default |
| `diskGiB as int` | one new disk in GiB; 0 for none |
| `network as string` | network id for one NIC; `""` for none |
| `networkType as string` | that network's type; `""` for `STANDARD_PORTGROUP` |

### `Version`

| Field | Meaning |
|---|---|
| `product as string` | e.g. `VMware vCenter Server` |
| `version as string` | e.g. `8.0.2.00100` |
| `build as string` | build number |
| `type as string` | deployment type |
| `releasedate as string` | e.g. `2023-12-05` |

### `VmSummary`

| Field | Meaning |
|---|---|
| `vm as string` | VM id |
| `name as string` | VM name |
| `powerState as string` | `POWERED_ON`, `POWERED_OFF` or `SUSPENDED` |
| `cpuCount as int` | virtual CPUs |
| `memoryMiB as int` | memory in MiB |

### `GuestIdentity`

| Field | Meaning |
|---|---|
| `name as string` | guest OS id, e.g. `UBUNTU_64` |
| `family as string` | e.g. `LINUX` |
| `fullName as string` | e.g. `Ubuntu Linux (64-bit)` |
| `hostName as string` | the guest's host name |
| `ipAddress as string` | its primary IP address |

### `Host`

| Field | Meaning |
|---|---|
| `host as string` | host id |
| `name as string` | host name |
| `connectionState as string` | `CONNECTED`, `DISCONNECTED`, `NOT_RESPONDING` |
| `powerState as string` | `POWERED_ON`, `POWERED_OFF`, `STANDBY` |

### `Cluster`

| Field | Meaning |
|---|---|
| `cluster as string` | cluster id |
| `name as string` | cluster name |
| `haEnabled as bool` | vSphere HA is on |
| `drsEnabled as bool` | DRS is on |

### `Datastore`

| Field | Meaning |
|---|---|
| `datastore as string` | datastore id |
| `name as string` | datastore name |
| `type as string` | `VMFS`, `NFS`, `VSAN`, ... |
| `capacity as int` | size, bytes |
| `freeSpace as int` | bytes free |

### `Item`

| Field | Meaning |
|---|---|
| `id as string` | object id |
| `name as string` | object name |
| `type as string` | network or folder type; `""` otherwise |

### `Task`

| Field | Meaning |
|---|---|
| `id as string` | task id |
| `status as string` | `PENDING`, `RUNNING`, `BLOCKED`, `SUCCEEDED`, `FAILED` |
| `description as string` | what it does |
| `progress as int` | percent done |
| `result as string` | the result; a string as it is, else JSON |
| `error as string` | why it failed |

### `LinuxCustomization`

| Field | Meaning |
|---|---|
| `hostName as string` | host name |
| `domain as string` | domain name; required |
| `timeZone as string` | e.g. `Europe/Vienna`; `""` keeps it |
| `ipAddress as string` | first NIC's IPv4 address; `""` for DHCP |
| `prefix as int` | its prefix length |
| `gateway as string` | default gateway |
| `dnsServers as list of string` | DNS servers |
| `dnsSuffixes as list of string` | DNS search suffixes |

### `Disk`

| Field | Meaning |
|---|---|
| `disk as string` | disk id, e.g. `2000` |
| `label as string` | e.g. `Hard disk 1` |
| `type as string` | `SCSI`, `SATA`, `NVME`, `IDE` |
| `capacity as int` | size, bytes |
| `file as string` | its VMDK |

### `Nic`

| Field | Meaning |
|---|---|
| `nic as string` | NIC id, e.g. `4000` |
| `label as string` | e.g. `Network adapter 1` |
| `type as string` | e.g. `VMXNET3` |
| `macAddress as string` | MAC address |
| `state as string` | `CONNECTED`, `NOT_CONNECTED`, ... |
| `network as string` | network id |
| `networkType as string` | network type |
| `startConnected as bool` | connects at power-on |

### `Category`

| Field | Meaning |
|---|---|
| `id as string` | category id |
| `name as string` | name |
| `description as string` | description |
| `cardinality as string` | `SINGLE` or `MULTIPLE` |

### `Tag`

| Field | Meaning |
|---|---|
| `id as string` | tag id |
| `name as string` | name |
| `description as string` | description |
| `categoryId as string` | its category |

### `GuestInterface`

| Field | Meaning |
|---|---|
| `nic as string` | virtual NIC id; `""` for none |
| `macAddress as string` | MAC address |
| `addresses as list of string` | addresses with prefix |

### `GuestCredentials`

| Field | Meaning |
|---|---|
| `user as string` | guest user |
| `password as string` | its password |

### `GuestProcess`

| Field | Meaning |
|---|---|
| `pid as int` | process id |
| `finished as bool` | it has ended |
| `exitCode as int` | its exit code |

## Client

| Function | Returns | Does |
|---|---|---|
| `vmware.client(address)` | `Client` | a client for `host`, `host:port` or a URL |
| `vmware.withSession(c, session)` | `Client` | use a session id kept from an earlier `login` |
| `vmware.withCaCert(c, pem)` | `Client` | trust this PEM certificate too |
| `vmware.withInsecure(c)` | `Client` | accept any certificate |
| `vmware.withTimeout(c, ms)` | `Client` | idle timeout per request |
| `vmware.withRetries(c, n)` | `Client` | retry a GET answered 429 or 5xx |
| `vmware.withPollInterval(c, ms)` | `Client` | how often the wait functions ask |
| `vmware.login(c, username, password)` | `Client` | open a session |
| `vmware.logout(c)` | `Client` | end it |
| `vmware.ensureSession(c, username, password)` | `Client` | check the session, log in again when it has ended |
| `vmware.describe(c)` | `string` | the client for a log line, without its session |

## Any endpoint

`path` is `/api/...` with any query string.

| Function | Returns | Does |
|---|---|---|
| `vmware.query(params)` | `string` | `?k=v&k=v2...` from a `map of string to list of string` |
| `vmware.call(c, method, path, body)` | `json.Value` | any method; a `null` body sends none |
| `vmware.get(c, path)` | `json.Value` | GET |
| `vmware.post(c, path, body)` | `json.Value` | POST |
| `vmware.put(c, path, body)` | `json.Value` | PUT |
| `vmware.patch(c, path, body)` | `json.Value` | PATCH |
| `vmware.delete(c, path)` | `json.Value` | DELETE |

## VMs

| Function | Returns | Does |
|---|---|---|
| `vmware.vms(c, filter)` | `list of VmSummary` | the VMs a filter selects |
| `vmware.vmByName(c, name)` | `VmSummary` | the one VM with this name |
| `vmware.vm(c, vm)` | `json.Value` | everything about one VM |
| `vmware.powerState(c, vm)` | `string` | its power state |
| `vmware.powerOn(c, vm)` | `null` | power on |
| `vmware.powerOff(c, vm)` | `null` | cut the power |
| `vmware.suspend(c, vm)` | `null` | suspend |
| `vmware.reset(c, vm)` | `null` | reset |
| `vmware.shutdownGuest(c, vm)` | `null` | ask the guest OS to shut down (Tools) |
| `vmware.rebootGuest(c, vm)` | `null` | ask the guest OS to reboot (Tools) |
| `vmware.guestIdentity(c, vm)` | `GuestIdentity` | guest OS, host name, IP (Tools) |

## Creating and deleting

| Function | Returns | Does |
|---|---|---|
| `vmware.createSpec(spec)` | `json.Value` | the request body for a `VmSpec`, to change before `createVmFrom` |
| `vmware.createVm(c, spec)` | `string` | create a VM, powered off; returns its id |
| `vmware.createVmFrom(c, body)` | `string` | create a VM from a full request body |
| `vmware.cloneVm(c, source, name, placement, powerOn)` | `string` | clone a VM |
| `vmware.findLibraryItem(c, name)` | `string` | the id of the content library item with this name |
| `vmware.deployTemplate(c, item, name, placement, powerOn)` | `string` | deploy a VM from a library VM template |
| `vmware.deleteVm(c, vm)` | `null` | delete a powered-off VM and its disks |
| `vmware.cloneVmTask(c, source, name, placement, powerOn)` | `string` | clone as a task; returns the task id |

## Tasks

| Function | Returns | Does |
|---|---|---|
| `vmware.startTask(c, method, path, body)` | `string` | start an operation with `vmw-task=true` |
| `vmware.taskStatus(c, id)` | `Task` | where a task stands |
| `vmware.waitTask(c, id, timeoutMs)` | `Task` | wait until it ends; 0 waits for ever |

## Guest customization

| Function | Returns | Does |
|---|---|---|
| `vmware.customizationSpecs(c)` | `list of Item` | the stored specs |
| `vmware.customize(c, vm, specName)` | `null` | apply a stored spec at the next power-on |
| `vmware.linuxSpec(lc)` | `json.Value` | a Linux spec, to change before `customizeWith` |
| `vmware.customizeWith(c, vm, spec)` | `null` | apply a spec given in full |
| `vmware.customizeLinux(c, vm, lc)` | `null` | apply a Linux spec |

## Hardware

| Function | Returns | Does |
|---|---|---|
| `vmware.setCpu(c, vm, count)` | `null` | virtual CPUs |
| `vmware.setMemory(c, vm, mib)` | `null` | memory in MiB |
| `vmware.disks(c, vm)` | `list of Disk` | the virtual disks |
| `vmware.addDisk(c, vm, gib)` | `string` | add an empty disk; returns its id |
| `vmware.removeDisk(c, vm, disk)` | `null` | detach a disk; the VMDK stays |
| `vmware.nics(c, vm)` | `list of Nic` | the network adapters |
| `vmware.addNic(c, vm, network, networkType)` | `string` | add a VMXNET3 adapter |
| `vmware.connectNic(c, vm, nic)` | `null` | plug it in |
| `vmware.disconnectNic(c, vm, nic)` | `null` | unplug it |
| `vmware.removeNic(c, vm, nic)` | `null` | remove it |

## Tags

| Function | Returns | Does |
|---|---|---|
| `vmware.categories(c)` | `list of Category` | the tag categories |
| `vmware.tags(c)` | `list of Tag` | the tags |
| `vmware.createCategory(c, name, cardinality)` | `string` | a new category; `SINGLE` or `MULTIPLE` |
| `vmware.createTag(c, categoryId, name)` | `string` | a new tag |
| `vmware.deleteTag(c, tag)` | `null` | delete a tag |
| `vmware.deleteCategory(c, category)` | `null` | delete a category and its tags |
| `vmware.attachTag(c, tag, vm)` | `null` | tag a VM |
| `vmware.detachTag(c, tag, vm)` | `null` | untag it |
| `vmware.vmTags(c, vm)` | `list of string` | tag ids on a VM |
| `vmware.taggedVms(c, tag)` | `list of string` | VM ids with a tag |

## Inside the guest

Needs VMware Tools running in the guest.

| Function | Returns | Does |
|---|---|---|
| `vmware.guestInterfaces(c, vm)` | `list of GuestInterface` | every interface and address |
| `vmware.guestAddresses(c, vm)` | `list of string` | addresses without loopback and link-local |
| `vmware.runInGuest(c, vm, creds, path, arguments)` | `int` | start a program; returns its pid |
| `vmware.guestProcess(c, vm, creds, pid)` | `GuestProcess` | where it stands |
| `vmware.waitGuestProcess(c, vm, creds, pid, timeoutMs)` | `GuestProcess` | wait until it ends |

## Inventory

| Function | Returns | Does |
|---|---|---|
| `vmware.version(c)` | `Version` | the appliance's version |
| `vmware.hosts(c)` | `list of Host` | the ESXi hosts |
| `vmware.clusters(c)` | `list of Cluster` | the clusters |
| `vmware.datastores(c)` | `list of Datastore` | the datastores |
| `vmware.datacenters(c)` | `list of Item` | the datacenters |
| `vmware.networks(c)` | `list of Item` | the networks |
| `vmware.folders(c, type)` | `list of Item` | the folders of a type; `""` for all |
| `vmware.resourcePools(c)` | `list of Item` | the resource pools |
