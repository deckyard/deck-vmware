# @deckyard/vmware

[![test](https://github.com/deckyard/deck-vmware/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-vmware/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-vmware/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-vmware)](https://github.com/deckyard/deck-vmware/releases/latest)

A [Jennifer](https://jennifer-lang.dev/) client for the vSphere Automation
REST API of vCenter (`/api`, vCenter 7.0 U2 and newer). `get`, `post`,
`put`, `patch` and `delete` reach every endpoint; typed verbs cover the
inventory (VMs, hosts, clusters, datacenters, datastores, networks, folders,
resource pools), creating, cloning, deploying and deleting VMs, tasks,
guest customization, CPU, memory, disks and NICs, tags, VM power, the
guest's addresses, and running programs in the guest. A standalone ESXi host
serves only the SOAP API and is not supported.

**Infrastructure as Code (IaC).** VMs, their hardware, guest customization
and tags can be provisioned from a Jennifer program kept in version control
and reviewed like any other code. The create, clone and deploy verbs are not
idempotent, and `addDisk` and `addNic` add a device on every run. A
re-runnable script lists what exists first (`vms`, `disks`, `nics`, `tags`);
`setCpu` and `setMemory` can be applied again. There is no plan or diff step,
and the deck does not detect drift.

**[Documentation](https://deckyard.github.io/deck-vmware/)**

## Install

```sh
jvc add @deckyard/vmware
```

Or unpack `src/` from a release archive (`deckyard-vmware-<version>.tar.gz`)
into `vendor/deckyard/vmware/`.

## Usage

```jennifer
use io;
import "@deckyard/vmware/" as vmware;

def c as vmware.Client init vmware.client("vcenter.example.com");
$c = vmware.withCaCert($c, fs.readBytes("vmca-root.pem"));
$c = vmware.login($c, "automation@vsphere.local", os.getEnv("VC_PASSWORD"));

def f as vmware.VmFilter;
$f.powerStates = [vmware.POWERED_OFF];
for (def vm in vmware.vms($c, $f)) {
    io.printf("%s %s\n", $vm.vm, $vm.name);
}
vmware.powerOn($c, vmware.vmByName($c, "web01").vm);

$c = vmware.logout($c);
```

## Requirements

Jennifer 0.26.0 or newer and the default `jennifer` binary: the deck needs
the `net` capability, which `jennifer-tiny` lacks.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/vmware_test.j      # the test overlay, offline
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

The tests answer from a fake server on a loopback port. The examples need a
real vCenter; see their headers.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

VMware, vSphere, vCenter and ESXi are trademarks of Broadcom. This deck is
not affiliated with or endorsed by Broadcom.
