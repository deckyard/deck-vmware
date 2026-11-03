<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Connecting

`vmware.client` takes a host name, `host:port` or a full URL; a bare host gets
`https://`.

```jennifer
import "@deckyard/vmware/" as vmware;

def c as vmware.Client init vmware.client("vcenter.example.com");
$c = vmware.withTimeout($c, 30000);
```

## Certificates

vCenter's certificate is signed by its own CA, the VMCA, unless it was
replaced. Download the root from `https://<vcenter>/certs/download.zip` (the
`.0` file under `certs/lin/` is PEM) and trust it:

```jennifer
$c = vmware.withCaCert($c, fs.readBytes("vmca-root.pem"));
```

`vmware.withInsecure($c)` accepts any certificate. The traffic is still
encrypted, but anyone in the path can read the password, so keep it for a
lab.

## Sessions

`vmware.login` sends the user name and password once, with Basic
authentication, to `POST /api/session`. vCenter answers with a session id,
which every later request carries in the `vmware-api-session-id` header.

```jennifer
$c = vmware.login($c, "automation@vsphere.local", os.getEnv("VC_PASSWORD"));
# ... work ...
$c = vmware.logout($c);
```

A session ends after 30 minutes without a request (vCenter's default) or at
`vmware.logout`. A request on an ended session fails with `HTTP 401
UNAUTHENTICATED`; log in again. A program that runs often can keep
`$c.session` and restore it with `vmware.withSession`.

A long-running program calls `vmware.ensureSession` before each batch of
work. It checks the session, which also restarts vCenter's idle timer, and
logs in again only when the session has ended:

```jennifer
$c = vmware.ensureSession($c, "automation@vsphere.local", os.getEnv("VC_PASSWORD"));
```

The session id grants full access while it lasts. Never print or log the
client itself; `vmware.describe($c)` gives a line without it.

Give the program an account of its own with only the privileges it needs.
vCenter limits the number of open sessions, so log out when done.

## Any endpoint

The [API reference](https://developer.broadcom.com/xapis/vsphere-automation-api/latest/)
lists every endpoint. Pass the path with its query string; `vmware.query`
builds one, repeating a key for each value as vSphere's filters expect:

```jennifer
def path as string init "/api/vcenter/vm" + vmware.query({"power_states": ["POWERED_ON"], "hosts": ["host-12", "host-14"]});
def running as json.Value init vmware.get($c, $path);

def tag as json.Value init vmware.post($c, "/api/cis/tagging/tag",
    json.decode('{"name": "backup", "category_id": "urn:vmomi:InventoryServiceTag:0e8d...:GLOBAL"}'));
vmware.patch($c, "/api/vcenter/vm/vm-42/hardware/memory", json.decode('{"size_MiB": 8192}'));
vmware.delete($c, "/api/cis/tagging/tag/" + json.asString($tag));
```

`vmware.call($c, method, path, body)` takes the method as a string. A body of
JSON `null` (`json.decode("null")`) sends none. A reply of `204 No Content`
comes back as JSON `null`.

Paths must start with `/` and hold no `..`, `#` or `//` and at most one `?`,
so a path built from input cannot send the session elsewhere. Encode an id
from input with `uri.encode`.
