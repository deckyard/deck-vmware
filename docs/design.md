<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

`@deckyard/vmware` is a client for vCenter™'s vSphere™ Automation REST API
(`/api`, vCenter 7.0 U2 and newer) over HTTPS: inventory (VMs, hosts,
clusters, datacenters, datastores, networks, folders, resource pools),
creating, cloning, deploying and deleting VMs, power, tasks, guest
customization, CPU, memory, disks and NICs, tags, guest networking and
running programs in the guest. `get`, `post`, `put`, `patch` and `delete`
reach any other endpoint.

Not in scope:

- **A standalone ESXi™ host.** ESXi serves only the SOAP API (vSphere Web
  Services); hosts are managed through their vCenter. The deck targets
  vCenter because its REST API is the clean, documented surface.
- **vCenter before 7.0 U2.** Those versions have only the older `/rest` API
  (its error shape is still read).
- **Snapshots, growing a disk, host maintenance mode.** The REST API has none
  of them, as far as known; they need SOAP.
- **Guest file copies and OVF deployment** have no typed functions; `post`
  reaches them.
- **`jennifer-tiny`.** It has no `net` capability.

## Decisions

- **Session login.** `login` posts to `/api/session` with Basic credentials
  and keeps the returned session id, sent on every request in
  `SESSION_HEADER` (`vmware-api-session-id`); `logout` deletes it.
  `ensureSession` checks the session (which also restarts vCenter's idle
  timer) and logs in again only when it has ended (HTTP 401).
- **One request path.** Every request goes through one function that checks
  the path, sets headers, sends and decodes the reply. Paths carry their
  query string; `query` builds repeated keys (`?k=v&k=v2`) as vSphere's list
  filters take them.
- **Detail lists over one connection.** `disks`, `nics`, `categories` and
  `tags` list ids and then fetch each entry over one kept-alive connection,
  instead of opening a TLS connection per entry; they stop at the first
  refusal.
- **Tasks.** `startTask` asks for the task form of an operation and returns
  the task id; `waitTask` polls `/api/cis/tasks/<id>` until it succeeds or
  fails, and a failed task's embedded error reads like a refused request.
  `cloneVm` blocks until the copy is done, `cloneVmTask` returns the task.
  `waitGuestProcess` polls a guest program the same way.
- **Specs as JSON.** `createSpec` returns the request body as a
  `json.Value`, so a caller can add settings `VmSpec` lacks before
  `createVmFrom`. Only fields that were set are emitted; NIC backing
  defaults to a standard port group.
- **Ambiguity is an error.** `vmByName` and `findLibraryItem` fail on
  duplicate names rather than picking one. `linuxSpec` requires a host name
  and a domain; `createCategory` accepts only `SINGLE` or `MULTIPLE`.
- **Retries.** Only GETs are retried (`withRetries`, 429 and 5xx, 500 ms
  backoff); writes never. Task and guest-process polls tolerate up to
  `MAX_POLL_FAILURES` (5) consecutive 5xx answers, timeouts or connections
  that never reached vCenter (a `net.NetError` with `sent` false), but never
  a 4xx (an ended session does not heal by waiting) nor a connection reset
  after the request went out.
- **Sibling of `@deckyard/proxmox`.** Same builder pattern, path checks, JSON
  readers, task waits and fake-server overlay, so a fix in one usually
  applies to the other.

## Errors

- Every error of kind `"vmware"` (`ERROR_KIND`) is a `VmwareError`:
  `status` is the HTTP status of a refused request, 0 for a local check or
  a transport failure. The message reads `HTTP <status> <TYPE>: <messages>`,
  from either the `/api` or the older `/rest` error shape. Callers branch on
  `status`, never on the message.
- A reply over its size cap stays kind `"limit"`, message
  `vmware: <verb> <path>: ...`.
- A vCenter that cannot be reached (refused, reset, unreachable, DNS, TLS,
  a close before any reply) is the `http` module's `net.NetError`, kind
  `"net"`, passed on unchanged so its `reason`, `sent` and `replied` stay
  readable.
- Any other transport failure, such as a timeout, is rewrapped as a
  `VmwareError` with status 0.
- The poll loops pass on anything else not of kind `"vmware"` unchanged.

## Security and limits

- HTTPS only: a bare host gets `https://`. vCenter usually presents a
  certificate from its own CA: `withCaCert` trusts it, `withInsecure` turns
  verification off.
- Paths are checked: `..`, `#`, `//`, CR, LF, spaces and a second `?` are
  refused, so a caller path cannot send the session elsewhere. Object ids in
  paths are encoded.
- `Client.session` grants full access; `describe` prints a client without
  it, for logs.
- Each request has a timeout (`withTimeout`); a large `cloneVm` needs a
  raised one, or `cloneVmTask`.

## Testing and validation

- `src/vmware_test.j` (33 tests) is a white-box overlay against a loopback
  fake built on `httpd`: one canned reply per request, with each request's
  method, path, query, authorization, session header, content type and body
  recorded. An unreachable server is `127.0.0.1:1`.
- The examples need a vCenter and credentials, so CI only parses them.

## Known limitations and open questions

- The SOAP-only operations (snapshots, disk growth, maintenance mode) and
  ESXi without vCenter.
- Tests asserting a multi-key query string depend on the map iteration
  order.

## Dependencies on the interpreter

- Floor `jennifer >=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms); the default binary only. The tests use the
  UTF-8 codecs of `encoding.encode` / `decode`, new in 0.27.0.
- The bundled `http` (send, keep-alive connections with `http.connect` and
  `http.exchange`, TLS options, retries) and `uri` modules; `httpd` in the
  tests.
- Thrown structs classified by kind (`jennifer` `6abf345`, the error-struct
  work of M28.51 to M28.57), and transport failures as `net.NetError` with
  `sent` (M28.65).
