<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/vmware

A client for the vSphere Automation REST API of vCenter: the JSON API under
`/api`, in vCenter 7.0 U2 and newer. `get`, `post`, `put`, `patch` and
`delete` reach every endpoint and return the reply as a `json.Value`. Typed
verbs cover the inventory (VMs, hosts, clusters, datacenters, datastores,
networks, folders, resource pools), creating, cloning, deploying and
deleting VMs, tasks, guest customization, CPU, memory, disks and NICs,
tags, VM power, the guest's addresses and identity, and running programs
in the guest.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/vmware/" as vmware;

def c as vmware.Client init vmware.client("vcenter.example.com");
$c = vmware.login($c, "administrator@vsphere.local", os.getEnv("VC_PASSWORD"));
io.printf("%s\n", vmware.version($c).version);
```

A `Client` is a value. `login`, `logout` and the `with*` functions return a
changed copy, so assign the result back to `$c`.

Objects are known by their managed object id: `vm-42`, `host-12`,
`domain-c8` (a cluster), `datastore-15`. The typed verbs take and return
these ids; names are not unique in vSphere.

## Errors

Every failure is `Error{kind: "vmware"}`, with a message that starts with
`vmware:` and names the request:

- a refused request: `vmware: POST /api/vcenter/vm/vm-42/power: HTTP 400 ALREADY_IN_DESIRED_STATE: Virtual machine is already powered on.`
  The error type and message are vSphere's own.
- a network failure or timeout, with the `http` module's message.
- a reply that is not JSON, a login without a session id, an empty object
  id, an API path that could leave the host, a name that matches no VM or
  several.

```jennifer
try {
    vmware.powerOn($c, "vm-42");
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

`HTTP 401 UNAUTHENTICATED` means the session has ended: log in again. Writes
are never retried; `withRetries` retries only GETs answered 429 or 5xx.

## What is not here

- **A standalone ESXi host.** ESXi serves only the SOAP API (vSphere Web
  Services), which this deck does not speak. Manage ESXi hosts through the
  vCenter they belong to.
- **vCenter before 7.0 U2.** Those versions have only the older `/rest` API.
- **Snapshots, growing a disk and host maintenance mode.** The REST API
  has none of them, as far as we could find; they need the SOAP API.
- **Copying files into or out of the guest** and **OVF deployment** have no
  typed functions; reach them through `post`.

## Requirements

Jennifer 0.25.0 or newer, default `jennifer` binary: the deck needs the `net`
capability, which `jennifer-tiny` lacks.
