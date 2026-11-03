<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Inside the guest

Everything here needs VMware Tools running in the guest; without it vCenter
answers `SERVICE_UNAVAILABLE`.

## Addresses

`vmware.guestAddresses` returns every address the guest reports, without
loopback and link-local ones; `vmware.guestInterfaces` returns each
interface with its MAC address, prefixes and virtual NIC.
`vmware.guestIdentity` gives only the primary address.

```jennifer
import "@deckyard/vmware/" as vmware;

io.printf("%s\n", strings.join(vmware.guestAddresses($c, "vm-42"), ", "));
```

Tools starts with the guest, so right after power-on the list may be empty
for a while.

## Running programs

`vmware.runInGuest` starts a program as an account inside the guest and
returns its process id; `vmware.waitGuestProcess` waits for it to end and
gives its exit code. vCenter keeps a finished process for five minutes.

```jennifer
def root as vmware.GuestCredentials init vmware.GuestCredentials{user: "root", password: os.getEnv("GUEST_PASSWORD")};
def pid as int init vmware.runInGuest($c, "vm-42", $root, "/bin/sh", "-c \"apt-get -y upgrade > /tmp/upgrade.log 2>&1\"");
def p as vmware.GuestProcess init vmware.waitGuestProcess($c, "vm-42", $root, $pid, 600000);
io.printf("exit %d\n", $p.exitCode);
```

Output is not captured: redirect it to a file on Linux, or run through
`c:\windows\system32\cmd.exe /c` on Windows. The account needs the
`VirtualMachine.GuestOperations.Execute` privilege in vCenter as well as a
login in the guest. Copying files in and out is not wrapped yet.
