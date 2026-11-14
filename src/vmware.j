# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the vSphere Automation REST API of vCenter (`/api`, vCenter
 * 7.0 U2 and newer).
 *
 * A thin client: `get`, `post`, `put`, `patch` and `delete` reach any
 * endpoint and return the reply as a `json.Value`. Typed verbs cover the
 * inventory (VMs, hosts, clusters, datacenters, datastores, networks,
 * folders, resource pools) and VM power. A standalone ESXi host does not
 * serve this API.
 *
 * `login` opens a session with a user name and password; the session id
 * rides along on every request until `logout`. vCenter usually presents a
 * certificate from its own CA (VMCA): trust it with `withCaCert`, or turn
 * checking off with `withInsecure`. Every failure is a `VmwareError` (kind
 * `"vmware"`) carrying the HTTP `status` vCenter answered; a reply over its
 * size cap is kind `"limit"`.
 *
 * @module vmware
 * @see https://developer.broadcom.com/xapis/vsphere-automation-api/latest/
 * @example
 *   def c as vmware.Client init vmware.client("vcenter.example.com");
 *   $c = vmware.login($c, "administrator@vsphere.local", "secret");
 *   def all as vmware.VmFilter;
 *   for (def vm in vmware.vms($c, $all)) {
 *       io.printf("%s %s %s\n", $vm.vm, $vm.name, $vm.powerState);
 *   }
 *   vmware.logout($c);
 */
use convert;
use json;
use lists;
use strings;
use time;
import "http.j" as http;
import "uri.j" as uri;

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "vmware";

/** Failed status checks in a row after which the wait functions give up. */
export def const MAX_POLL_FAILURES as int init 5;

/** The header that carries the session id. */
export def const SESSION_HEADER as string init "vmware-api-session-id";

/** Power state of a running VM or host. */
export def const POWERED_ON as string init "POWERED_ON";

/** Power state of a VM or host that is off. */
export def const POWERED_OFF as string init "POWERED_OFF";

/** Power state of a suspended VM. */
export def const SUSPENDED as string init "SUSPENDED";

/**
 * A connection to one vCenter. Build it with `client` and the `with*`
 * functions; each returns a changed copy. `session` grants full access
 * while it lasts: log `describe($c)`, never the client.
 *
 * @field url {string} base URL, `https://host`, no trailing slash
 * @field session {string} session id from `login`; "" for none
 * @field tls {http.TlsOptions} certificate checking
 * @field timeoutMs {int} idle timeout per request in milliseconds; 0 for the `http` default
 * @field retries {int} retries of a GET answered 429 or 5xx
 * @field pollMs {int} interval between status checks in `waitTask` and
 *   `waitGuestProcess`
 */
export def struct Client {
    url as string,
    session as string,
    tls as http.TlsOptions,
    timeoutMs as int,
    retries as int,
    pollMs as int
};

/**
 * Which VMs `vms` lists. Every list narrows the result; an empty list does
 * not filter. The zero `VmFilter` lists every VM (vCenter stops at 4000).
 *
 * @field vms {list of string} VM ids, e.g. `vm-42`
 * @field names {list of string} exact VM names
 * @field powerStates {list of string} `POWERED_ON`, `POWERED_OFF`, `SUSPENDED`
 * @field hosts {list of string} host ids, e.g. `host-12`
 * @field clusters {list of string} cluster ids, e.g. `domain-c8`
 * @field datacenters {list of string} datacenter ids, e.g. `datacenter-3`
 * @field folders {list of string} folder ids, e.g. `group-v4`
 * @field resourcePools {list of string} resource pool ids, e.g. `resgroup-9`
 */
export def struct VmFilter {
    vms as list of string,
    names as list of string,
    powerStates as list of string,
    hosts as list of string,
    clusters as list of string,
    datacenters as list of string,
    folders as list of string,
    resourcePools as list of string
};

/**
 * The version of the vCenter appliance.
 *
 * @field product {string} e.g. `VMware vCenter Server`
 * @field version {string} e.g. `8.0.2.00100`
 * @field build {string} build number
 * @field type {string} e.g. `vCenter Server with an embedded Platform Services Controller`
 * @field releasedate {string} e.g. `2023-12-05`
 */
export def struct Version {
    product as string,
    version as string,
    build as string,
    type as string,
    releasedate as string
};

/**
 * A VM as `vms` lists it.
 *
 * @field vm {string} VM id, e.g. `vm-42`
 * @field name {string} VM name
 * @field powerState {string} `POWERED_ON`, `POWERED_OFF` or `SUSPENDED`
 * @field cpuCount {int} virtual CPUs
 * @field memoryMiB {int} memory in MiB
 */
export def struct VmSummary {
    vm as string,
    name as string,
    powerState as string,
    cpuCount as int,
    memoryMiB as int
};

/**
 * What VMware Tools reports about the guest operating system.
 *
 * @field name {string} guest OS id, e.g. `UBUNTU_64`
 * @field family {string} e.g. `LINUX`, `WINDOWS`
 * @field fullName {string} e.g. `Ubuntu Linux (64-bit)`
 * @field hostName {string} the guest's host name
 * @field ipAddress {string} its primary IP address; "" when unknown
 */
export def struct GuestIdentity {
    name as string,
    family as string,
    fullName as string,
    hostName as string,
    ipAddress as string
};

/**
 * An ESXi host.
 *
 * @field host {string} host id, e.g. `host-12`
 * @field name {string} host name
 * @field connectionState {string} `CONNECTED`, `DISCONNECTED` or `NOT_RESPONDING`
 * @field powerState {string} `POWERED_ON`, `POWERED_OFF` or `STANDBY`
 */
export def struct Host {
    host as string,
    name as string,
    connectionState as string,
    powerState as string
};

/**
 * A cluster.
 *
 * @field cluster {string} cluster id, e.g. `domain-c8`
 * @field name {string} cluster name
 * @field haEnabled {bool} vSphere HA is on
 * @field drsEnabled {bool} DRS is on
 */
export def struct Cluster {
    cluster as string,
    name as string,
    haEnabled as bool,
    drsEnabled as bool
};

/**
 * A datastore.
 *
 * @field datastore {string} datastore id, e.g. `datastore-15`
 * @field name {string} datastore name
 * @field type {string} `VMFS`, `NFS`, `NFS41`, `VSAN`, `VVOL`, ...
 * @field capacity {int} size, bytes
 * @field freeSpace {int} bytes free
 */
export def struct Datastore {
    datastore as string,
    name as string,
    type as string,
    capacity as int,
    freeSpace as int
};

/**
 * A datacenter, a network, a folder or a resource pool: an inventory object
 * known by id and name.
 *
 * @field id {string} object id, e.g. `datacenter-3`, `network-17`, `group-v4`
 * @field name {string} object name
 * @field type {string} the network or folder type (`STANDARD_PORTGROUP`,
 *   `VIRTUAL_MACHINE`, ...); "" for datacenters and resource pools
 */
export def struct Item {
    id as string,
    name as string,
    type as string
};

/**
 * Where a new VM goes. Fill what vCenter needs: a folder, and a resource
 * pool, cluster or host for the compute; a datastore for the disks. Empty
 * fields are left out and vCenter picks or refuses.
 *
 * @field folder {string} VM folder id, e.g. `group-v4`
 * @field resourcePool {string} resource pool id, e.g. `resgroup-9`
 * @field cluster {string} cluster id, e.g. `domain-c8`
 * @field host {string} host id, e.g. `host-12`
 * @field datastore {string} datastore id, e.g. `datastore-15`
 */
export def struct Placement {
    folder as string,
    resourcePool as string,
    cluster as string,
    host as string,
    datastore as string
};

/**
 * A new VM for `createVm`: the common settings. For anything else, build the
 * body with `createSpec`, change it, and pass it to `createVmFrom`.
 *
 * @field name {string} VM name
 * @field guestOs {string} guest OS id, e.g. `UBUNTU_64`, `WINDOWS_2019_SERVER_64`
 * @field placement {Placement} where it goes
 * @field cpuCount {int} virtual CPUs; 0 for vCenter's default
 * @field memoryMiB {int} memory in MiB; 0 for vCenter's default
 * @field diskGiB {int} size of one new disk in GiB; 0 for no disk
 * @field network {string} network id for one NIC, e.g. `network-17`; "" for no NIC
 * @field networkType {string} that network's type, as `networks` reports it;
 *   "" means `STANDARD_PORTGROUP`
 */
export def struct VmSpec {
    name as string,
    guestOs as string,
    placement as Placement,
    cpuCount as int,
    memoryMiB as int,
    diskGiB as int,
    network as string,
    networkType as string
};

/**
 * A vCenter task, from an operation started with `vmw-task=true`.
 *
 * @field id {string} the task id
 * @field status {string} `PENDING`, `RUNNING`, `BLOCKED`, `SUCCEEDED` or `FAILED`
 * @field description {string} what it does
 * @field progress {int} percent done; 0 when vCenter does not say
 * @field result {string} the operation's result: a string as it is (the new
 *   VM's id for a clone), anything else as JSON; "" for none
 * @field error {string} why it failed; "" unless `FAILED`
 */
export def struct Task {
    id as string,
    status as string,
    description as string,
    progress as int,
    result as string,
    error as string
};

/**
 * Guest customization for a Linux VM: identity, DNS and the first NIC.
 *
 * @field hostName {string} host name
 * @field domain {string} domain name; required by vCenter
 * @field timeZone {string} e.g. `Europe/Vienna`; "" for the template's
 * @field ipAddress {string} IPv4 address of the first NIC; "" for DHCP
 * @field prefix {int} its prefix length, e.g. 24
 * @field gateway {string} default gateway; "" for none
 * @field dnsServers {list of string} DNS servers
 * @field dnsSuffixes {list of string} DNS search suffixes
 */
export def struct LinuxCustomization {
    hostName as string,
    domain as string,
    timeZone as string,
    ipAddress as string,
    prefix as int,
    gateway as string,
    dnsServers as list of string,
    dnsSuffixes as list of string
};

/**
 * A virtual disk.
 *
 * @field disk {string} disk id within the VM, e.g. `2000`
 * @field label {string} e.g. `Hard disk 1`
 * @field type {string} `SCSI`, `SATA`, `NVME` or `IDE`
 * @field capacity {int} size, bytes
 * @field file {string} its VMDK, e.g. `[nvme] web/web.vmdk`
 */
export def struct Disk {
    disk as string,
    label as string,
    type as string,
    capacity as int,
    file as string
};

/**
 * A virtual network adapter.
 *
 * @field nic {string} NIC id within the VM, e.g. `4000`
 * @field label {string} e.g. `Network adapter 1`
 * @field type {string} e.g. `VMXNET3`, `E1000E`
 * @field macAddress {string} its MAC address
 * @field state {string} `CONNECTED`, `NOT_CONNECTED` or `RECOVERABLE_ERROR`
 * @field network {string} network id
 * @field networkType {string} `STANDARD_PORTGROUP`, `DISTRIBUTED_PORTGROUP`, ...
 * @field startConnected {bool} connects when the VM powers on
 */
export def struct Nic {
    nic as string,
    label as string,
    type as string,
    macAddress as string,
    state as string,
    network as string,
    networkType as string,
    startConnected as bool
};

/**
 * A tag category.
 *
 * @field id {string} category id, `urn:vmomi:InventoryServiceCategory:...`
 * @field name {string} category name
 * @field description {string} its description
 * @field cardinality {string} `SINGLE` (one tag per object) or `MULTIPLE`
 */
export def struct Category {
    id as string,
    name as string,
    description as string,
    cardinality as string
};

/**
 * A tag.
 *
 * @field id {string} tag id, `urn:vmomi:InventoryServiceTag:...`
 * @field name {string} tag name
 * @field description {string} its description
 * @field categoryId {string} its category
 */
export def struct Tag {
    id as string,
    name as string,
    description as string,
    categoryId as string
};

/**
 * A network interface as VMware Tools reports it.
 *
 * @field nic {string} the virtual NIC id; "" for an interface without one
 * @field macAddress {string} its MAC address
 * @field addresses {list of string} addresses with prefix, e.g. `10.0.0.5/24`
 */
export def struct GuestInterface {
    nic as string,
    macAddress as string,
    addresses as list of string
};

/**
 * An account inside the guest, for guest operations.
 *
 * @field user {string} user name
 * @field password {string} its password
 */
export def struct GuestCredentials {
    user as string,
    password as string
};

/**
 * A process started in the guest.
 *
 * @field pid {int} process id
 * @field finished {bool} whether it has ended
 * @field exitCode {int} its exit code, once finished
 */
export def struct GuestProcess {
    pid as int,
    finished as bool,
    exitCode as int
};

/**
 * A failed request or a refused value. Every error of kind `"vmware"` is one,
 * so its fields are safe to read once the kind matches.
 *
 * @field kind {string} always `"vmware"` (`ERROR_KIND`)
 * @field message {string} `vmware: ` and what failed, for a refused request `<verb> <path>: HTTP <status>: <reason>`
 * @field status {int} the HTTP status vCenter answered (400, 401, 403, 404, 500, ...); 0 when no answer was read or the failure is a local check
 */
export def struct VmwareError {
    kind as string,
    message as string,
    status as int
};

/**
 * Raise a deck error.
 *
 * @param message {string} what went wrong
 * @throws {VmwareError} always, with `kind` `"vmware"` and status 0
 */
func fail(message as string) {
    failStatus($message, 0);
}

# failStatus throws the VmwareError of a refused request, with its status.
func failStatus(message as string, status as int) {
    throw VmwareError{kind: ERROR_KIND, message: "vmware: " + $message, status: $status};
}

# failTransport throws the error of a request that got no usable answer: a
# reached cap (an `http` body cap) stays kind "limit", anything else is a
# VmwareError; the message is `vmware: <verb> <path>: <cause>` either way.
func failTransport(what as string, e as Error) {
    if ($e.kind == "limit") {
        throw Error{kind: "limit", message: "vmware: " + $what + ": " + $e.message};
    }
    fail($what + ": " + $e.message);
}

/**
 * The base URL for a host name or URL. A bare host gets `https://`; a
 * trailing slash and a trailing `/api` are dropped.
 *
 * @param address {string} `vcenter.example.com`, `10.0.0.5:443` or `https://vc/`
 * @return {string} `https://host[:port]`
 */
func baseUrl(address as string) {
    def url as string init strings.trim($address);
    if ($url == "") {
        fail("the host is empty");
    }
    while (strings.endsWith($url, "/")) {
        $url = strings.substring($url, 0, len($url) - 1);
    }
    if (strings.endsWith($url, "/api")) {
        $url = strings.substring($url, 0, len($url) - len("/api"));
    }
    if (strings.contains($url, "://")) {
        return $url;
    }
    if (not strings.startsWith($url, "[") and
        strings.indexOf($url, ":") != strings.lastIndexOf($url, ":")) {
        $url = "[" + $url + "]";
    }
    return "https://" + $url;
}

/**
 * A client for a vCenter, with no session yet.
 *
 * @param address {string} host name, `host:port` or a full `https://` URL
 * @return {Client} the client; full certificate checking, 1 s polling
 * @throws {VmwareError} kind `"vmware"` when the address is empty
 */
export func client(address as string) {
    def c as Client;
    $c.url = baseUrl($address);
    $c.pollMs = 1000;
    return $c;
}

/**
 * Use a session id from an earlier `login`, for example one kept in a file.
 *
 * @param c {Client} the client
 * @param session {string} the session id
 * @return {Client} the changed copy
 */
export func withSession(c as Client, session as string) {
    $c.session = $session;
    return $c;
}

/**
 * Trust a certificate (PEM) in addition to the system's, such as the VMCA
 * root from `https://<vcenter>/certs/download.zip`.
 *
 * @param c {Client} the client
 * @param pem {bytes} the certificate
 * @return {Client} the changed copy
 */
export func withCaCert(c as Client, pem as bytes) {
    $c.tls.caCert = $pem;
    $c.tls.skipVerify = false;
    return $c;
}

/**
 * Accept any certificate. The connection is still encrypted but no longer
 * authenticated; prefer `withCaCert`.
 *
 * @param c {Client} the client
 * @return {Client} the changed copy
 */
export func withInsecure(c as Client) {
    $c.tls.skipVerify = true;
    return $c;
}

/**
 * Set the idle timeout of each request.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds; 0 for the `http` default
 * @return {Client} the changed copy
 */
export func withTimeout(c as Client, ms as int) {
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * Retry a GET answered 429 or 5xx. Other methods are never retried.
 *
 * @param c {Client} the client
 * @param n {int} retries, 0 for none
 * @return {Client} the changed copy
 */
export func withRetries(c as Client, n as int) {
    $c.retries = $n;
    return $c;
}

/**
 * Set how often `waitTask` and `waitGuestProcess` ask.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds between checks
 * @return {Client} the changed copy
 */
export func withPollInterval(c as Client, ms as int) {
    $c.pollMs = $ms;
    return $c;
}

/**
 * Open a session. It ends after 30 minutes without a request (vCenter's
 * default), or at `logout`.
 *
 * @param c {Client} the client
 * @param username {string} e.g. `administrator@vsphere.local`
 * @param password {string} the password
 * @return {Client} the copy holding the session id
 * @throws {VmwareError} kind `"vmware"` when the login is refused
 */
export func login(c as Client, username as string, password as string) {
    def anon as Client init $c;
    $anon.session = "";
    def headers as map of string to string init {"Authorization": http.basic($username, $password)};
    def reply as json.Value init send($anon, "POST", "/api/session", $headers, "");
    def session as string init "";
    if (json.typeOf($reply) == "string") {
        $session = json.asString($reply);
    }
    if ($session == "") {
        fail("the login reply holds no session id");
    }
    return withSession($c, $session);
}

/**
 * End the session.
 *
 * @param c {Client} a client holding a session
 * @return {Client} the copy without it
 * @throws {VmwareError} kind `"vmware"` when the client has no session, or as `call`
 */
export func logout(c as Client) {
    if ($c.session == "") {
        fail("logout needs a session from login");
    }
    delete($c, "/api/session");
    return withSession($c, "");
}

/**
 * A query string from parameters. A key with several values is repeated,
 * the form vSphere's list filters take.
 *
 * @param params {map of string to list of string} the parameters
 * @return {string} `?a=1&a=2&b=3`; "" when no parameter has a value
 * @example
 *   vmware.get($c, "/api/vcenter/vm" + vmware.query({"power_states": ["POWERED_ON"]}));
 */
export func query(params as map of string to list of string) {
    def parts as list of string init [];
    for (def key in $params) {
        for (def value in $params[$key]) {
            $parts[] = uri.encodeForm($key) + "=" + uri.encodeForm($value);
        }
    }
    if (len($parts) == 0) {
        return "";
    }
    return "?" + strings.join($parts, "&");
}

/**
 * Refuse a path that could send the session somewhere else.
 *
 * @param path {string} an API path such as `/api/vcenter/vm?names=web`
 * @throws {VmwareError} kind `"vmware"` unless the path starts with one `/` and has
 *   no `..`, `#` or `//`, nor a second `?`
 */
func ensurePath(path as string) {
    if (not strings.startsWith($path, "/")) {
        fail("an API path starts with /, got \"" + $path + "\"");
    }
    for (def bad in ["..", "#", "//", "\r", "\n", " "]) {
        if (strings.contains($path, $bad)) {
            fail("an API path holds no \"" + $bad + "\": " + $path);
        }
    }
    if (strings.indexOf($path, "?") != strings.lastIndexOf($path, "?")) {
        fail("an API path holds one query string at most: " + $path);
    }
}

/**
 * Send one request and decode the reply.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method, upper case
 * @param path {string} the path, with its query string
 * @param headers {map of string to string} extra headers
 * @param body {string} the JSON body; "" for none
 * @return {json.Value} the reply; JSON `null` for an empty one
 */
func send(
    c as Client,
    method as string,
    path as string,
    headers as map of string to string,
    body as string) {
    ensurePath($path);
    $headers["Accept"] = "application/json";
    if ($c.session != "") {
        $headers[SESSION_HEADER] = $c.session;
    }
    if ($body != "") {
        $headers["Content-Type"] = "application/json";
    }
    def o as http.Options;
    $o.tls = $c.tls;
    $o.timeoutMs = $c.timeoutMs;
    if ($method == "GET") {
        $o.maxRetries = $c.retries;
        $o.backoffMs = 500;
    }
    def r as http.Response;
    try {
        $r = http.send($method, $c.url + $path, $headers, $body, $o);
    } catch (e) {
        failTransport($method + " " + $path, $e);
    }
    return decodeReply($r, $method + " " + $path);
}

/**
 * The JSON of a reply, or a deck error for a refusal.
 *
 * @param r {http.Response} the reply
 * @param what {string} the request, for the error message
 * @return {json.Value} the reply; JSON `null` for an empty one
 */
func decodeReply(r as http.Response, what as string) {
    if ($r.status < 200 or $r.status >= 300) {
        failStatus($what + ": " + failureText($r), $r.status);
    }
    if (strings.trim($r.body) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($r.body);
    } catch (e) {
        fail($what + ": the reply is not JSON");
    }
}

/**
 * GET several paths over one kept-alive connection. A list followed by one
 * request per entry would otherwise open a TLS connection per entry.
 *
 * @param c {Client} the client
 * @param paths {list of string} the paths
 * @return {list of json.Value} the replies, in order
 */
func getMany(c as Client, paths as list of string) {
    def out as list of json.Value init [];
    if (len($paths) == 0) {
        return $out;
    }
    for (def path in $paths) {
        ensurePath($path);
    }
    def headers as map of string to string init {"Accept": "application/json"};
    if ($c.session != "") {
        $headers[SESSION_HEADER] = $c.session;
    }
    def o as http.Options;
    $o.tls = $c.tls;
    $o.timeoutMs = $c.timeoutMs;
    def s as http.Session;
    try {
        $s = http.connect($c.url, $o);
    } catch (e) {
        failTransport("GET " + $paths[0], $e);
    }
    for (def path in $paths) {
        def ex as http.Exchange;
        try {
            $ex = http.exchange($s, "GET", $path, $headers, "");
        } catch (e) {
            http.close($s);
            failTransport("GET " + $path, $e);
        }
        $s = $ex.session;
        try {
            $out[] = decodeReply($ex.response, "GET " + $path);
        } catch (e) {
            http.close($s);
            throw $e;
        }
    }
    http.close($s);
    return $out;
}

/**
 * The detail paths of a list of ids.
 *
 * @param prefix {string} the path before the id, ending in `/`
 * @param ids {list of string} the ids
 * @return {list of string} one path per id
 */
func detailPaths(prefix as string, ids as list of string) {
    def out as list of string init [];
    for (def id in $ids) {
        $out[] = $prefix + segment($id);
    }
    return $out;
}

/**
 * Call any endpoint.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param path {string} the path, `/api/...`, with any query string (see `query`)
 * @param body {json.Value} the request body; JSON `null` sends none
 * @return {json.Value} the reply; JSON `null` for an empty one (204)
 * @throws {VmwareError} kind `"vmware"` on a bad path, a network failure or a reply
 *   that is not 2xx; the message names the status, vSphere's error type and
 *   its message
 */
export func call(c as Client, method as string, path as string, body as json.Value) {
    def verb as string init strings.upper($method);
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE"], $verb)) {
        fail("unsupported method " + $method);
    }
    def text as string init "";
    if (json.typeOf($body) != "null") {
        $text = json.encode($body);
    }
    return send($c, $verb, $path, {}, $text);
}

/**
 * GET an endpoint.
 *
 * @param c {Client} the client
 * @param path {string} the path, with any query string
 * @return {json.Value} the reply
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func get(c as Client, path as string) {
    return send($c, "GET", $path, {}, "");
}

/**
 * POST to an endpoint.
 *
 * @param c {Client} the client
 * @param path {string} the path, with any query string
 * @param body {json.Value} the request body; JSON `null` sends none
 * @return {json.Value} the reply; often the new object's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func post(c as Client, path as string, body as json.Value) {
    return call($c, "POST", $path, $body);
}

/**
 * PUT to an endpoint.
 *
 * @param c {Client} the client
 * @param path {string} the path, with any query string
 * @param body {json.Value} the request body
 * @return {json.Value} the reply
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func put(c as Client, path as string, body as json.Value) {
    return call($c, "PUT", $path, $body);
}

/**
 * PATCH an endpoint, changing only the fields in `body`.
 *
 * @param c {Client} the client
 * @param path {string} the path, with any query string
 * @param body {json.Value} the fields to change
 * @return {json.Value} the reply
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func patch(c as Client, path as string, body as json.Value) {
    return call($c, "PATCH", $path, $body);
}

/**
 * DELETE an endpoint.
 *
 * @param c {Client} the client
 * @param path {string} the path, with any query string
 * @return {json.Value} the reply
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func delete(c as Client, path as string) {
    return send($c, "DELETE", $path, {}, "");
}

/**
 * Explain a refused request. `/api` answers
 * `{"error_type": "NOT_FOUND", "messages": [{"default_message": ...}]}`;
 * the older `/rest` wraps the same in `type` and `value`.
 *
 * @param r {http.Response} the reply
 * @return {string} `HTTP <status> <error type>: <messages>`
 */
func failureText(r as http.Response) {
    def text as string init "HTTP " + convert.toString($r.status);
    def doc as json.Value init json.decode("null");
    try {
        $doc = json.decode($r.body);
    } catch (e) {
        $doc = json.decode("null");
    }
    if (json.typeOf($doc) != "map") {
        if (strings.trim($r.statusText) != "") {
            return $text + ": " + strings.trim($r.statusText);
        }
        return $text;
    }
    def kind as string init field($doc, "/error_type");
    def base as string init "";
    if ($kind == "" and kindAt($doc, "/value") == "map") {
        $kind = field($doc, "/type");
        $base = "/value";
    }
    if ($kind != "") {
        def dot as int init strings.lastIndexOf($kind, ".");
        $text = $text + " " + strings.upper(strings.substring($kind, $dot + 1));
    }
    def said as list of string init [];
    for (def p in items(getAt($doc, $base + "/messages"))) {
        def m as string init strings.trim(field(
            getAt($doc, $base + "/messages"),
            $p + "/default_message"));
        if ($m != "") {
            $said[] = $m;
        }
    }
    if (len($said) > 0) {
        $text = $text + ": " + strings.join($said, " ");
    }
    return $text;
}

/**
 * The type of a node, `missing` when the pointer does not resolve. Jennifer
 * 0.25.0's `json.typeOf` throws for a missing member instead.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer; "" for the root
 * @return {string} `null`, `bool`, `int`, `float`, `string`, `list`, `map` or `missing`
 */
func kindAt(v as json.Value, ptr as string) {
    if ($ptr == "") {
        return json.typeOf($v);
    }
    if (not json.has($v, $ptr)) {
        return "missing";
    }
    return json.typeOf($v, $ptr);
}

/**
 * The node at a pointer.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer; "" for the root
 * @return {json.Value} the node; JSON `null` when it is missing
 */
func getAt(v as json.Value, ptr as string) {
    if ($ptr == "") {
        return $v;
    }
    if (not json.has($v, $ptr)) {
        return json.decode("null");
    }
    return json.get($v, $ptr);
}

/**
 * Read a node as text.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the string, or the number as text; "" for anything else
 */
func field(v as json.Value, ptr as string) {
    def kind as string init kindAt($v, $ptr);
    if ($kind == "string") {
        return json.asString($v, $ptr);
    } elseif ($kind == "int") {
        return convert.toString(json.asInt($v, $ptr));
    }
    return "";
}

/**
 * Read a node as an int.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {int} the number, truncated; 0 for anything else
 */
func number(v as json.Value, ptr as string) {
    def kind as string init kindAt($v, $ptr);
    if ($kind == "int") {
        return json.asInt($v, $ptr);
    } elseif ($kind == "float") {
        return convert.toInt(json.asFloat($v, $ptr));
    }
    return 0;
}

/**
 * Read a node as a bool.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {bool} the flag; false for anything else
 */
func flag(v as json.Value, ptr as string) {
    if (kindAt($v, $ptr) == "bool") {
        return json.asBool($v, $ptr);
    }
    return false;
}

/**
 * The pointers of a list's elements.
 *
 * @param v {json.Value} the document
 * @return {list of string} `/0`, `/1`, ...; empty when `v` is not a list
 */
func items(v as json.Value) {
    def out as list of string init [];
    if (json.typeOf($v) != "list") {
        return $out;
    }
    def n as int init json.length($v);
    def i as int init 0;
    while ($i < $n) {
        $out[] = "/" + convert.toString($i);
        $i = $i + 1;
    }
    return $out;
}

/**
 * An id as a path segment.
 *
 * @param id {string} an object id such as `vm-42`
 * @return {string} the id, percent-encoded
 * @throws {VmwareError} kind `"vmware"` when the id is empty
 */
func segment(id as string) {
    if (strings.trim($id) == "") {
        fail("the object id is empty");
    }
    return uri.encode($id);
}

/**
 * The version of the vCenter appliance.
 *
 * @param c {Client} the client
 * @return {Version} the version
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func version(c as Client) {
    def d as json.Value init get($c, "/api/appliance/system/version");
    return Version{
        product: field($d, "/product"),
        version: field($d, "/version"),
        build: field($d, "/build"),
        type: field($d, "/type"),
        releasedate: field($d, "/releasedate")
    };
}

/**
 * The query string of a `VmFilter`.
 *
 * @param f {VmFilter} the filter
 * @return {string} `?names=...&power_states=...`; "" for the zero filter
 */
func vmQuery(f as VmFilter) {
    return query({
        "vms": $f.vms,
        "names": $f.names,
        "power_states": $f.powerStates,
        "hosts": $f.hosts,
        "clusters": $f.clusters,
        "datacenters": $f.datacenters,
        "folders": $f.folders,
        "resource_pools": $f.resourcePools
    });
}

/**
 * The VMs a filter selects.
 *
 * @param c {Client} the client
 * @param filter {VmFilter} which VMs; the zero `VmFilter` for all
 * @return {list of VmSummary} the VMs, in vCenter's order
 * @throws {VmwareError} kind `"vmware"` as `call`; vCenter refuses more than 4000
 *   VMs with `UNABLE_TO_ALLOCATE_RESOURCE`, so narrow the filter
 */
export func vms(c as Client, filter as VmFilter) {
    def d as json.Value init get($c, "/api/vcenter/vm" + vmQuery($filter));
    def out as list of VmSummary init [];
    for (def p in items($d)) {
        $out[] = VmSummary{
            vm: field($d, $p + "/vm"),
            name: field($d, $p + "/name"),
            powerState: field($d, $p + "/power_state"),
            cpuCount: number($d, $p + "/cpu_count"),
            memoryMiB: number($d, $p + "/memory_size_MiB")
        };
    }
    return $out;
}

/**
 * The one VM with this name.
 *
 * @param c {Client} the client
 * @param name {string} the exact name
 * @return {VmSummary} the VM
 * @throws {VmwareError} kind `"vmware"` when no VM or several VMs have the name
 */
export func vmByName(c as Client, name as string) {
    def f as VmFilter;
    $f.names = [$name];
    def found as list of VmSummary init vms($c, $f);
    if (len($found) == 0) {
        fail("no VM named \"" + $name + "\"");
    }
    if (len($found) > 1) {
        fail(convert.toString(len($found)) + " VMs are named \"" + $name + "\"");
    }
    return $found[0];
}

/**
 * Everything vCenter knows about a VM: hardware, CPU, memory, disks, NICs,
 * boot options.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {json.Value} the VM's description, vSphere's keys as they are
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func vm(c as Client, vm as string) {
    return get($c, "/api/vcenter/vm/" + segment($vm));
}

/**
 * The JSON of a placement, holding only the fields that are set.
 *
 * @param p {Placement} the placement
 * @param withDatastore {bool} whether to include the datastore
 * @return {json.Value} the placement object
 */
func placementJson(p as Placement, withDatastore as bool) {
    def v as json.Value init json.map();
    def fields as map of string to string init {
        "folder": $p.folder,
        "resource_pool": $p.resourcePool,
        "cluster": $p.cluster,
        "host": $p.host
    };
    if ($withDatastore) {
        $fields["datastore"] = $p.datastore;
    }
    for (def key in $fields) {
        if ($fields[$key] != "") {
            $v = json.set($v, "/" + $key, $fields[$key]);
        }
    }
    return $v;
}

/**
 * The request body `createVm` sends for a spec. Change it with `json.set`
 * for settings `VmSpec` does not have, then call `createVmFrom`.
 *
 * @param spec {VmSpec} the VM
 * @return {json.Value} the body of `POST /api/vcenter/vm`
 * @throws {VmwareError} kind `"vmware"` when the name or guest OS is empty
 */
export func createSpec(spec as VmSpec) {
    if ($spec.name == "" or $spec.guestOs == "") {
        fail("a new VM needs a name and a guest OS");
    }
    def v as json.Value init json.map();
    $v = json.set($v, "/name", $spec.name);
    $v = json.set($v, "/guest_OS", $spec.guestOs);
    $v = json.set($v, "/placement", placementJson($spec.placement, true));
    if ($spec.cpuCount > 0) {
        $v = json.set($v, "/cpu", json.map());
        $v = json.set($v, "/cpu/count", $spec.cpuCount);
    }
    if ($spec.memoryMiB > 0) {
        $v = json.set($v, "/memory", json.map());
        $v = json.set($v, "/memory/size_MiB", $spec.memoryMiB);
    }
    if ($spec.diskGiB > 0) {
        def disk as json.Value init json.map();
        $disk = json.set($disk, "/new_vmdk", json.map());
        $disk = json.set($disk, "/new_vmdk/capacity", $spec.diskGiB * 1073741824);
        $v = json.set($v, "/disks", json.list([$disk]));
    }
    if ($spec.network != "") {
        def kind as string init $spec.networkType;
        if ($kind == "") {
            $kind = "STANDARD_PORTGROUP";
        }
        def nic as json.Value init json.map();
        $nic = json.set($nic, "/start_connected", true);
        $nic = json.set($nic, "/backing", json.map());
        $nic = json.set($nic, "/backing/type", $kind);
        $nic = json.set($nic, "/backing/network", $spec.network);
        $v = json.set($v, "/nics", json.list([$nic]));
    }
    return $v;
}

/**
 * Create a VM, powered off.
 *
 * @param c {Client} the client
 * @param spec {VmSpec} the VM
 * @return {string} the new VM's id
 * @throws {VmwareError} kind `"vmware"` as `createSpec` and `call`
 */
export func createVm(c as Client, spec as VmSpec) {
    return createVmFrom($c, createSpec($spec));
}

/**
 * Create a VM from a full request body, as the API reference describes
 * `POST /api/vcenter/vm`.
 *
 * @param c {Client} the client
 * @param body {json.Value} the body, e.g. from `createSpec`
 * @return {string} the new VM's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func createVmFrom(c as Client, body as json.Value) {
    return idOf(post($c, "/api/vcenter/vm", $body), "createVm");
}

/**
 * The object id a create call returned.
 *
 * @param v {json.Value} the reply
 * @param what {string} the call, for the error message
 * @return {string} the id
 */
func idOf(v as json.Value, what as string) {
    if (json.typeOf($v) != "string" or json.asString($v) == "") {
        fail($what + " returned no id");
    }
    return json.asString($v);
}

/**
 * Clone a VM; the source may be running. Older vCenter releases lack this
 * endpoint and answer 404.
 *
 * Answers when the copy is done: raise `withTimeout` for a large VM.
 *
 * @param c {Client} the client
 * @param source {string} the VM to copy
 * @param name {string} the new VM's name
 * @param placement {Placement} where it goes; empty fields keep the source's
 * @param powerOn {bool} power it on when done
 * @return {string} the new VM's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func cloneVm(
    c as Client,
    source as string,
    name as string,
    placement as Placement,
    powerOn as bool) {
    def body as json.Value init cloneBody($source, $name, $placement, $powerOn);
    return idOf(post($c, "/api/vcenter/vm?action=clone", $body), "cloneVm");
}

/**
 * Find a content library item by its exact name.
 *
 * @param c {Client} the client
 * @param name {string} the item's name
 * @return {string} its id
 * @throws {VmwareError} kind `"vmware"` when no item or several items have the name
 */
export func findLibraryItem(c as Client, name as string) {
    def body as json.Value init json.set(json.map(), "/name", $name);
    def ids as json.Value init post($c, "/api/content/library/item?action=find", $body);
    def found as list of string init [];
    for (def p in items($ids)) {
        $found[] = field($ids, $p);
    }
    if (len($found) == 0) {
        fail("no library item named \"" + $name + "\"");
    }
    if (len($found) > 1) {
        fail(convert.toString(len($found)) + " library items are named \"" + $name + "\"");
    }
    return $found[0];
}

/**
 * Deploy a VM from a VM template in a content library. An OVF template in a
 * library deploys through a different endpoint, `/api/vcenter/ovf/library-item`.
 *
 * Answers when the copy is done: raise `withTimeout` for a large VM.
 *
 * @param c {Client} the client
 * @param item {string} the library item's id, e.g. from `findLibraryItem`
 * @param name {string} the new VM's name
 * @param placement {Placement} where it goes; `datastore` holds its disks
 * @param powerOn {bool} power it on when done
 * @return {string} the new VM's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func deployTemplate(
    c as Client,
    item as string,
    name as string,
    placement as Placement,
    powerOn as bool) {
    def v as json.Value init json.map();
    $v = json.set($v, "/name", $name);
    $v = json.set($v, "/placement", placementJson($placement, false));
    if ($placement.datastore != "") {
        $v = json.set($v, "/disk_storage", json.map());
        $v = json.set($v, "/disk_storage/datastore", $placement.datastore);
    }
    $v = json.set($v, "/powered_on", $powerOn);
    def path as string init "/api/vcenter/vm-template/library-items/" + segment($item) +
        "?action=deploy";
    return idOf(post($c, $path, $v), "deployTemplate");
}

/**
 * Delete a VM and its disks. vCenter refuses a VM that is not powered off.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing; the VM is gone when it returns
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func deleteVm(c as Client, vm as string) {
    delete($c, "/api/vcenter/vm/" + segment($vm));
    return null;
}

/**
 * A VM's power state.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {string} `POWERED_ON`, `POWERED_OFF` or `SUSPENDED`
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func powerState(c as Client, vm as string) {
    return field(get($c, "/api/vcenter/vm/" + segment($vm) + "/power"), "/state");
}

/**
 * Run a power action on the VM.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param scope {string} `power` for the virtual hardware, `guest/power` for the guest OS
 * @param action {string} the action
 * @return {null} nothing; the action is done when it returns
 */
func powerAction(c as Client, vm as string, scope as string, action as string) {
    send(
        $c,
        "POST",
        "/api/vcenter/vm/" + segment($vm) + "/" + $scope + "?action=" + $action,
        {},
        "");
    return null;
}

/**
 * Power a VM on.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing; the VM is on when it returns
 * @throws {VmwareError} kind `"vmware"` as `call`; `ALREADY_IN_DESIRED_STATE` when it is on
 */
export func powerOn(c as Client, vm as string) {
    return powerAction($c, $vm, "power", "start");
}

/**
 * Power a VM off at once, like pulling the plug.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func powerOff(c as Client, vm as string) {
    return powerAction($c, $vm, "power", "stop");
}

/**
 * Suspend a VM to disk.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func suspend(c as Client, vm as string) {
    return powerAction($c, $vm, "power", "suspend");
}

/**
 * Reset a VM, like pressing its reset button.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func reset(c as Client, vm as string) {
    return powerAction($c, $vm, "power", "reset");
}

/**
 * Ask the guest OS to shut down. Needs VMware Tools running in the guest;
 * returns once the request is delivered, not when the VM is off.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`; `SERVICE_UNAVAILABLE` without Tools
 */
export func shutdownGuest(c as Client, vm as string) {
    return powerAction($c, $vm, "guest/power", "shutdown");
}

/**
 * Ask the guest OS to reboot. Needs VMware Tools.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func rebootGuest(c as Client, vm as string) {
    return powerAction($c, $vm, "guest/power", "reboot");
}

/**
 * What VMware Tools reports about the guest.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {GuestIdentity} the identity
 * @throws {VmwareError} kind `"vmware"` as `call`; `SERVICE_UNAVAILABLE` while
 *   Tools is not running
 */
export func guestIdentity(c as Client, vm as string) {
    def d as json.Value init get($c, "/api/vcenter/vm/" + segment($vm) + "/guest/identity");
    return GuestIdentity{
        name: field($d, "/name"),
        family: field($d, "/family"),
        fullName: field($d, "/full_name/default_message"),
        hostName: field($d, "/host_name"),
        ipAddress: field($d, "/ip_address")
    };
}

/**
 * The ESXi hosts.
 *
 * @param c {Client} the client
 * @return {list of Host} the hosts
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func hosts(c as Client) {
    def d as json.Value init get($c, "/api/vcenter/host");
    def out as list of Host init [];
    for (def p in items($d)) {
        $out[] = Host{
            host: field($d, $p + "/host"),
            name: field($d, $p + "/name"),
            connectionState: field($d, $p + "/connection_state"),
            powerState: field($d, $p + "/power_state")
        };
    }
    return $out;
}

/**
 * The clusters.
 *
 * @param c {Client} the client
 * @return {list of Cluster} the clusters
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func clusters(c as Client) {
    def d as json.Value init get($c, "/api/vcenter/cluster");
    def out as list of Cluster init [];
    for (def p in items($d)) {
        $out[] = Cluster{
            cluster: field($d, $p + "/cluster"),
            name: field($d, $p + "/name"),
            haEnabled: flag($d, $p + "/ha_enabled"),
            drsEnabled: flag($d, $p + "/drs_enabled")
        };
    }
    return $out;
}

/**
 * The datastores.
 *
 * @param c {Client} the client
 * @return {list of Datastore} the datastores
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func datastores(c as Client) {
    def d as json.Value init get($c, "/api/vcenter/datastore");
    def out as list of Datastore init [];
    for (def p in items($d)) {
        $out[] = Datastore{
            datastore: field($d, $p + "/datastore"),
            name: field($d, $p + "/name"),
            type: field($d, $p + "/type"),
            capacity: number($d, $p + "/capacity"),
            freeSpace: number($d, $p + "/free_space")
        };
    }
    return $out;
}

/**
 * Fold a list of inventory objects.
 *
 * @param d {json.Value} the reply
 * @param idKey {string} the member holding the id
 * @return {list of Item} the objects
 */
func itemsFrom(d as json.Value, idKey as string) {
    def out as list of Item init [];
    for (def p in items($d)) {
        $out[] = Item{
            id: field($d, $p + "/" + $idKey),
            name: field($d, $p + "/name"),
            type: field($d, $p + "/type")
        };
    }
    return $out;
}

/**
 * The datacenters.
 *
 * @param c {Client} the client
 * @return {list of Item} the datacenters
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func datacenters(c as Client) {
    return itemsFrom(get($c, "/api/vcenter/datacenter"), "datacenter");
}

/**
 * The networks: standard port groups, distributed port groups, opaque
 * networks.
 *
 * @param c {Client} the client
 * @return {list of Item} the networks; `type` tells them apart
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func networks(c as Client) {
    return itemsFrom(get($c, "/api/vcenter/network"), "network");
}

/**
 * The folders.
 *
 * @param c {Client} the client
 * @param type {string} `VIRTUAL_MACHINE`, `HOST`, `DATACENTER`, `DATASTORE`,
 *   `NETWORK`; "" for every folder
 * @return {list of Item} the folders
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func folders(c as Client, type as string) {
    def params as map of string to list of string init {};
    if ($type != "") {
        $params["type"] = [$type];
    }
    return itemsFrom(get($c, "/api/vcenter/folder" + query($params)), "folder");
}

/**
 * The resource pools.
 *
 * @param c {Client} the client
 * @return {list of Item} the resource pools
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func resourcePools(c as Client) {
    return itemsFrom(get($c, "/api/vcenter/resource-pool"), "resource_pool");
}

/**
 * A path with `vmw-task=true` added to its query string.
 *
 * @param path {string} the path
 * @return {string} the path asking for a task
 */
func taskPath(path as string) {
    if (strings.contains($path, "?")) {
        return $path + "&vmw-task=true";
    }
    return $path + "?vmw-task=true";
}

/**
 * Start an operation as a task: the call returns at once with a task id,
 * which `waitTask` follows. Only operations the API reference marks as
 * tasks accept it; others answer an error.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path, with any query string
 * @param body {json.Value} the request body; JSON `null` sends none
 * @return {string} the task id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func startTask(c as Client, method as string, path as string, body as json.Value) {
    return idOf(call($c, $method, taskPath($path), $body), "startTask");
}

/**
 * Where a task stands.
 *
 * @param c {Client} the client
 * @param id {string} the task id
 * @return {Task} the task
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func taskStatus(c as Client, id as string) {
    def d as json.Value init get($c, "/api/cis/tasks/" + segment($id));
    def t as Task init Task{
        id: $id,
        status: field($d, "/status"),
        description: field($d, "/description/default_message"),
        progress: 0,
        result: "",
        error: ""
    };
    def total as int init number($d, "/progress/total");
    if ($total > 0) {
        $t.progress = number($d, "/progress/completed") * 100 // $total;
    }
    def kind as string init kindAt($d, "/result");
    if ($kind == "string") {
        $t.result = json.asString($d, "/result");
    } elseif ($kind != "missing" and $kind != "null") {
        $t.result = json.encode(json.get($d, "/result"));
    }
    if (kindAt($d, "/error") == "map") {
        def r as http.Response;
        $r.status = 0;
        $r.body = json.encode(json.get($d, "/error"));
        $t.error = strings.trim(strings.substring(failureText($r), len("HTTP 0")));
    }
    return $t;
}

/**
 * Wait until a task ends, asking every `pollMs`; a network
 * failure or a 5xx answer is retried (see `withPollInterval`).
 *
 * @param c {Client} the client
 * @param id {string} the task id
 * @param timeoutMs {int} how long to wait; 0 waits for ever
 * @return {Task} the ended task; it worked when `status` is `SUCCEEDED`
 * @throws {VmwareError} kind `"vmware"` when the time runs out, after
 *   `MAX_POLL_FAILURES` failed checks in a row, or on a 4xx answer
 */
export func waitTask(c as Client, id as string, timeoutMs as int) {
    def started as time.Time init time.now();
    def failures as int init 0;
    def last as string init "PENDING";
    while (true) {
        def t as Task;
        def answered as bool init true;
        try {
            $t = taskStatus($c, $id);
        } catch (e) {
            $answered = false;
            # only the deck's own failures can be retried; a cap, a
            # cancellation or a fault passes on at once
            if ($e.kind != ERROR_KIND) {
                throw $e;
            }
            $failures = retryOrThrow($e, $failures);
        }
        if ($answered) {
            if ($t.status == "SUCCEEDED" or $t.status == "FAILED") {
                return $t;
            }
            $failures = 0;
            $last = $t.status;
        }
        def waited as int init time.milliseconds(time.sub(time.now(), $started));
        if ($timeoutMs > 0 and $waited >= $timeoutMs) {
            fail("task " + $id + " still " + $last + " after " + convert.toString($timeoutMs) +
                " ms");
        }
        time.sleep(time.fromMilliseconds(pollDelay($c)));
    }
}

/**
 * The body of a clone request.
 *
 * @param source {string} the VM to copy
 * @param name {string} the new name
 * @param placement {Placement} where it goes
 * @param powerOn {bool} power it on when done
 * @return {json.Value} the body
 */
func cloneBody(source as string, name as string, placement as Placement, powerOn as bool) {
    def v as json.Value init json.map();
    $v = json.set($v, "/source", $source);
    $v = json.set($v, "/name", $name);
    $v = json.set($v, "/placement", placementJson($placement, true));
    $v = json.set($v, "/power_on", $powerOn);
    return $v;
}

/**
 * Clone a VM as a task: returns at once, and `waitTask` follows the copy.
 * The finished task's `result` is the new VM's id.
 *
 * @param c {Client} the client
 * @param source {string} the VM to copy
 * @param name {string} the new VM's name
 * @param placement {Placement} where it goes; empty fields keep the source's
 * @param powerOn {bool} power it on when done
 * @return {string} the task id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func cloneVmTask(
    c as Client,
    source as string,
    name as string,
    placement as Placement,
    powerOn as bool) {
    return startTask(
        $c,
        "POST",
        "/api/vcenter/vm?action=clone",
        cloneBody($source, $name, $placement, $powerOn));
}

/**
 * The customization specifications stored in vCenter.
 *
 * @param c {Client} the client
 * @return {list of Item} the specs: `id` and `name` are the spec's name,
 *   `type` its OS type (`LINUX` or `WINDOWS`)
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func customizationSpecs(c as Client) {
    def d as json.Value init get($c, "/api/vcenter/guest/customization-specs");
    def out as list of Item init [];
    for (def p in items($d)) {
        def name as string init field($d, $p + "/name");
        $out[] = Item{id: $name, name: $name, type: field($d, $p + "/os_type")};
    }
    return $out;
}

/**
 * Apply a stored customization specification. The VM must be powered off;
 * the guest is customized at its next power-on (VMware Tools needed).
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param specName {string} the spec's name
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func customize(c as Client, vm as string, specName as string) {
    def body as json.Value init json.set(json.map(), "/name", $specName);
    put($c, "/api/vcenter/vm/" + segment($vm) + "/guest/customization", $body);
    return null;
}

/**
 * A customization specification for a Linux guest, to change before
 * `customizeWith`.
 *
 * @param lc {LinuxCustomization} the settings
 * @return {json.Value} the `spec` object
 * @throws {VmwareError} kind `"vmware"` when the host name or domain is empty
 */
export func linuxSpec(lc as LinuxCustomization) {
    if ($lc.hostName == "" or $lc.domain == "") {
        fail("a Linux customization needs a host name and a domain");
    }
    def linux as json.Value init json.map();
    $linux = json.set($linux, "/hostname", json.map());
    $linux = json.set($linux, "/hostname/type", "FIXED");
    $linux = json.set($linux, "/hostname/fixed_name", $lc.hostName);
    $linux = json.set($linux, "/domain", $lc.domain);
    if ($lc.timeZone != "") {
        $linux = json.set($linux, "/time_zone", $lc.timeZone);
    }
    def ipv4 as json.Value init json.set(json.map(), "/type", "DHCP");
    if ($lc.ipAddress != "") {
        $ipv4 = json.set($ipv4, "/type", "STATIC");
        $ipv4 = json.set($ipv4, "/ip_address", $lc.ipAddress);
        $ipv4 = json.set($ipv4, "/prefix", $lc.prefix);
        if ($lc.gateway != "") {
            $ipv4 = json.set($ipv4, "/gateways", json.list([$lc.gateway]));
        }
    }
    def adapter as json.Value init json.set(json.map(), "/ipv4", $ipv4);
    def nic as json.Value init json.set(json.map(), "/adapter", $adapter);
    def dns as json.Value init json.map();
    $dns = json.set($dns, "/dns_servers", json.list($lc.dnsServers));
    $dns = json.set($dns, "/dns_suffix_list", json.list($lc.dnsSuffixes));
    def spec as json.Value init json.map();
    $spec = json.set($spec, "/configuration_spec", json.set(json.map(), "/linux_config", $linux));
    $spec = json.set($spec, "/global_DNS_settings", $dns);
    $spec = json.set($spec, "/interfaces", json.list([$nic]));
    return $spec;
}

/**
 * Apply a customization specification given in full. The VM must be
 * powered off; the guest is customized at its next power-on.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param spec {json.Value} the spec, e.g. from `linuxSpec`
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func customizeWith(c as Client, vm as string, spec as json.Value) {
    def body as json.Value init json.set(json.map(), "/spec", $spec);
    put($c, "/api/vcenter/vm/" + segment($vm) + "/guest/customization", $body);
    return null;
}

/**
 * Customize a Linux guest: `customizeWith` and `linuxSpec`.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id, powered off
 * @param lc {LinuxCustomization} the settings
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `linuxSpec` and `call`
 */
export func customizeLinux(c as Client, vm as string, lc as LinuxCustomization) {
    return customizeWith($c, $vm, linuxSpec($lc));
}

/**
 * The path of a VM's hardware.
 *
 * @param vm {string} the VM id
 * @param part {string} e.g. `cpu`, `disk`, `ethernet`
 * @return {string} `/api/vcenter/vm/<vm>/hardware/<part>`
 */
func hardwarePath(vm as string, part as string) {
    return "/api/vcenter/vm/" + segment($vm) + "/hardware/" + $part;
}

/**
 * Set the number of virtual CPUs. A running VM needs CPU hot add enabled.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param count {int} virtual CPUs
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func setCpu(c as Client, vm as string, count as int) {
    patch($c, hardwarePath($vm, "cpu"), json.set(json.map(), "/count", $count));
    return null;
}

/**
 * Set the memory. A running VM needs memory hot add enabled, and can only
 * grow.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param mib {int} memory in MiB
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func setMemory(c as Client, vm as string, mib as int) {
    patch($c, hardwarePath($vm, "memory"), json.set(json.map(), "/size_MiB", $mib));
    return null;
}

/**
 * The ids of a hardware list, `[{"disk": "2000"}, ...]`.
 *
 * @param d {json.Value} the reply
 * @param key {string} the member holding the id
 * @return {list of string} the ids
 */
func idsOf(d as json.Value, key as string) {
    def out as list of string init [];
    for (def p in items($d)) {
        $out[] = field($d, $p + "/" + $key);
    }
    return $out;
}

/**
 * A VM's virtual disks. The details come over one kept-alive connection.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {list of Disk} the disks
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func disks(c as Client, vm as string) {
    def ids as list of string init idsOf(get($c, hardwarePath($vm, "disk")), "disk");
    def details as list of json.Value init getMany(
        $c,
        detailPaths(hardwarePath($vm, "disk/"), $ids));
    def out as list of Disk init [];
    def i as int init 0;
    while ($i < len($ids)) {
        def d as json.Value init $details[$i];
        $out[] = Disk{
            disk: $ids[$i],
            label: field($d, "/label"),
            type: field($d, "/type"),
            capacity: number($d, "/capacity"),
            file: field($d, "/backing/vmdk_file")
        };
        $i = $i + 1;
    }
    return $out;
}

/**
 * Add a new, empty disk.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param gib {int} its size in GiB
 * @return {string} the new disk's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func addDisk(c as Client, vm as string, gib as int) {
    def body as json.Value init json.set(json.map(), "/new_vmdk", json.map());
    $body = json.set($body, "/new_vmdk/capacity", $gib * 1073741824);
    return idOf(post($c, hardwarePath($vm, "disk"), $body), "addDisk");
}

/**
 * Remove a disk from the VM. The VMDK file stays on the datastore.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param disk {string} the disk id, from `disks`
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func removeDisk(c as Client, vm as string, disk as string) {
    delete($c, hardwarePath($vm, "disk/" + segment($disk)));
    return null;
}

/**
 * A VM's network adapters. The details come over one kept-alive connection.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {list of Nic} the NICs
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func nics(c as Client, vm as string) {
    def ids as list of string init idsOf(get($c, hardwarePath($vm, "ethernet")), "nic");
    def details as list of json.Value init getMany(
        $c,
        detailPaths(hardwarePath($vm, "ethernet/"), $ids));
    def out as list of Nic init [];
    def i as int init 0;
    while ($i < len($ids)) {
        def d as json.Value init $details[$i];
        $out[] = Nic{
            nic: $ids[$i],
            label: field($d, "/label"),
            type: field($d, "/type"),
            macAddress: field($d, "/mac_address"),
            state: field($d, "/state"),
            network: field($d, "/backing/network"),
            networkType: field($d, "/backing/type"),
            startConnected: flag($d, "/start_connected")
        };
        $i = $i + 1;
    }
    return $out;
}

/**
 * Add a VMXNET3 network adapter that connects at power-on.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param network {string} the network id
 * @param networkType {string} its type, as `networks` reports it; "" means
 *   `STANDARD_PORTGROUP`
 * @return {string} the new NIC's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func addNic(c as Client, vm as string, network as string, networkType as string) {
    def kind as string init $networkType;
    if ($kind == "") {
        $kind = "STANDARD_PORTGROUP";
    }
    def body as json.Value init json.map();
    $body = json.set($body, "/type", "VMXNET3");
    $body = json.set($body, "/start_connected", true);
    $body = json.set($body, "/backing", json.map());
    $body = json.set($body, "/backing/type", $kind);
    $body = json.set($body, "/backing/network", $network);
    return idOf(post($c, hardwarePath($vm, "ethernet"), $body), "addNic");
}

/**
 * Connect a NIC of a running VM, like plugging in its cable.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param nic {string} the NIC id, from `nics`
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func connectNic(c as Client, vm as string, nic as string) {
    send($c, "POST", hardwarePath($vm, "ethernet/" + segment($nic)) + "?action=connect", {}, "");
    return null;
}

/**
 * Disconnect a NIC of a running VM.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param nic {string} the NIC id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func disconnectNic(c as Client, vm as string, nic as string) {
    send($c, "POST", hardwarePath($vm, "ethernet/" + segment($nic)) + "?action=disconnect", {}, "");
    return null;
}

/**
 * Remove a NIC.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param nic {string} the NIC id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func removeNic(c as Client, vm as string, nic as string) {
    delete($c, hardwarePath($vm, "ethernet/" + segment($nic)));
    return null;
}

/**
 * The tag categories. The details come over one kept-alive connection.
 *
 * @param c {Client} the client
 * @return {list of Category} the categories
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func categories(c as Client) {
    def ids as list of string init stringsOf(get($c, "/api/cis/tagging/category"));
    def details as list of json.Value init getMany(
        $c,
        detailPaths("/api/cis/tagging/category/", $ids));
    def out as list of Category init [];
    def i as int init 0;
    while ($i < len($ids)) {
        def d as json.Value init $details[$i];
        $out[] = Category{
            id: $ids[$i],
            name: field($d, "/name"),
            description: field($d, "/description"),
            cardinality: field($d, "/cardinality")
        };
        $i = $i + 1;
    }
    return $out;
}

/**
 * The tags. The details come over one kept-alive connection.
 *
 * @param c {Client} the client
 * @return {list of Tag} the tags
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func tags(c as Client) {
    def ids as list of string init stringsOf(get($c, "/api/cis/tagging/tag"));
    def details as list of json.Value init getMany($c, detailPaths("/api/cis/tagging/tag/", $ids));
    def out as list of Tag init [];
    def i as int init 0;
    while ($i < len($ids)) {
        def d as json.Value init $details[$i];
        $out[] = Tag{
            id: $ids[$i],
            name: field($d, "/name"),
            description: field($d, "/description"),
            categoryId: field($d, "/category_id")
        };
        $i = $i + 1;
    }
    return $out;
}

/**
 * The strings of a list reply, such as a list of ids.
 *
 * @param d {json.Value} the reply
 * @return {list of string} the strings
 */
func stringsOf(d as json.Value) {
    def out as list of string init [];
    for (def p in items($d)) {
        $out[] = field($d, $p);
    }
    return $out;
}

/**
 * Create a tag category for every kind of object.
 *
 * @param c {Client} the client
 * @param name {string} category name
 * @param cardinality {string} `SINGLE` (one tag of it per object) or `MULTIPLE`
 * @return {string} the new category's id
 * @throws {VmwareError} kind `"vmware"` on another cardinality, or as `call`
 */
export func createCategory(c as Client, name as string, cardinality as string) {
    if ($cardinality != "SINGLE" and $cardinality != "MULTIPLE") {
        fail("a cardinality is SINGLE or MULTIPLE, got \"" + $cardinality + "\"");
    }
    def body as json.Value init json.map();
    $body = json.set($body, "/name", $name);
    $body = json.set($body, "/description", "");
    $body = json.set($body, "/cardinality", $cardinality);
    $body = json.set($body, "/associable_types", json.list());
    return idOf(post($c, "/api/cis/tagging/category", $body), "createCategory");
}

/**
 * Create a tag.
 *
 * @param c {Client} the client
 * @param categoryId {string} its category
 * @param name {string} tag name
 * @return {string} the new tag's id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func createTag(c as Client, categoryId as string, name as string) {
    def body as json.Value init json.map();
    $body = json.set($body, "/name", $name);
    $body = json.set($body, "/description", "");
    $body = json.set($body, "/category_id", $categoryId);
    return idOf(post($c, "/api/cis/tagging/tag", $body), "createTag");
}

/**
 * Delete a tag; it comes off every object.
 *
 * @param c {Client} the client
 * @param tag {string} the tag id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func deleteTag(c as Client, tag as string) {
    delete($c, "/api/cis/tagging/tag/" + segment($tag));
    return null;
}

/**
 * Delete a category and its tags.
 *
 * @param c {Client} the client
 * @param category {string} the category id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func deleteCategory(c as Client, category as string) {
    delete($c, "/api/cis/tagging/category/" + segment($category));
    return null;
}

/**
 * The `object_id` body of a tag association for a VM.
 *
 * @param vm {string} the VM id
 * @return {json.Value} `{"object_id": {"id": vm, "type": "VirtualMachine"}}`
 */
func vmObject(vm as string) {
    def ref as json.Value init json.set(json.map(), "/id", $vm);
    $ref = json.set($ref, "/type", "VirtualMachine");
    return json.set(json.map(), "/object_id", $ref);
}

/**
 * Attach a tag to a VM.
 *
 * @param c {Client} the client
 * @param tag {string} the tag id
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func attachTag(c as Client, tag as string, vm as string) {
    post($c, "/api/cis/tagging/tag-association/" + segment($tag) + "?action=attach", vmObject($vm));
    return null;
}

/**
 * Detach a tag from a VM.
 *
 * @param c {Client} the client
 * @param tag {string} the tag id
 * @param vm {string} the VM id
 * @return {null} nothing
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func detachTag(c as Client, tag as string, vm as string) {
    post($c, "/api/cis/tagging/tag-association/" + segment($tag) + "?action=detach", vmObject($vm));
    return null;
}

/**
 * The tags on a VM.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {list of string} the tag ids
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func vmTags(c as Client, vm as string) {
    def d as json.Value init post(
        $c,
        "/api/cis/tagging/tag-association?action=list-attached-tags",
        vmObject($vm));
    def out as list of string init [];
    for (def p in items($d)) {
        $out[] = field($d, $p);
    }
    return $out;
}

/**
 * The VMs a tag is attached to.
 *
 * @param c {Client} the client
 * @param tag {string} the tag id
 * @return {list of string} the VM ids; other kinds of object are left out
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func taggedVms(c as Client, tag as string) {
    def path as string init "/api/cis/tagging/tag-association/" + segment($tag) +
        "?action=list-attached-objects";
    def d as json.Value init post($c, $path, json.decode("null"));
    def out as list of string init [];
    for (def p in items($d)) {
        if (field($d, $p + "/type") == "VirtualMachine") {
            $out[] = field($d, $p + "/id");
        }
    }
    return $out;
}

/**
 * Every network interface VMware Tools reports in the guest.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id, running with Tools
 * @return {list of GuestInterface} the interfaces
 * @throws {VmwareError} kind `"vmware"` as `call`; `SERVICE_UNAVAILABLE` without Tools
 */
export func guestInterfaces(c as Client, vm as string) {
    def d as json.Value init get(
        $c,
        "/api/vcenter/vm/" + segment($vm) + "/guest/networking/interfaces");
    def out as list of GuestInterface init [];
    for (def p in items($d)) {
        def addrs as list of string init [];
        def ips as json.Value init getAt($d, $p + "/ip/ip_addresses");
        for (def q in items($ips)) {
            $addrs[] = field($ips, $q + "/ip_address") + "/" + field($ips, $q + "/prefix_length");
        }
        $out[] = GuestInterface{
            nic: field($d, $p + "/nic"),
            macAddress: field($d, $p + "/mac_address"),
            addresses: $addrs
        };
    }
    return $out;
}

/**
 * The guest's IP addresses, without prefix and without loopback
 * (127.0.0.0/8, ::1) and link-local ones (169.254.0.0/16, fe80::/10).
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @return {list of string} e.g. `["10.0.0.5", "2001:db8::5"]`
 * @throws {VmwareError} kind `"vmware"` as `guestInterfaces`
 */
export func guestAddresses(c as Client, vm as string) {
    def out as list of string init [];
    for (def i in guestInterfaces($c, $vm)) {
        for (def a in $i.addresses) {
            def ip as string init strings.split($a, "/")[0];
            if (not isLocalAddress($ip)) {
                $out[] = $ip;
            }
        }
    }
    return $out;
}

/**
 * The `credentials` object of a guest operation.
 *
 * @param creds {GuestCredentials} the account
 * @return {json.Value} the object
 */
func credentialsJson(creds as GuestCredentials) {
    def v as json.Value init json.map();
    $v = json.set($v, "/interactive_session", false);
    $v = json.set($v, "/type", "USERNAME_PASSWORD");
    $v = json.set($v, "/user_name", $creds.user);
    $v = json.set($v, "/password", $creds.password);
    return $v;
}

/**
 * Start a program in the guest. Needs VMware Tools and an account in the
 * guest. Output is not captured: redirect it to a file in `arguments`
 * (Linux) or run through `cmd.exe /c` (Windows).
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param creds {GuestCredentials} the guest account
 * @param path {string} absolute path of the program, e.g. `/bin/sh`
 * @param arguments {string} its arguments, e.g. `-c "systemctl restart nginx"`
 * @return {int} the process id
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func runInGuest(
    c as Client,
    vm as string,
    creds as GuestCredentials,
    path as string,
    arguments as string) {
    def spec as json.Value init json.set(json.map(), "/path", $path);
    $spec = json.set($spec, "/arguments", $arguments);
    def body as json.Value init json.set(json.map(), "/credentials", credentialsJson($creds));
    $body = json.set($body, "/spec", $spec);
    def reply as json.Value init post(
        $c,
        "/api/vcenter/vm/" + segment($vm) + "/guest/processes?action=create",
        $body);
    if (json.typeOf($reply) != "int") {
        fail("runInGuest returned no process id");
    }
    return json.asInt($reply);
}

/**
 * Where a guest process stands. vCenter keeps a finished process for five
 * minutes.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param creds {GuestCredentials} the guest account
 * @param pid {int} the process id, from `runInGuest`
 * @return {GuestProcess} the process
 * @throws {VmwareError} kind `"vmware"` as `call`
 */
export func guestProcess(c as Client, vm as string, creds as GuestCredentials, pid as int) {
    def path as string init "/api/vcenter/vm/" + segment($vm) + "/guest/processes/" +
        convert.toString($pid) + "?action=get";
    def d as json.Value init post(
        $c,
        $path,
        json.set(json.map(), "/credentials", credentialsJson($creds)));
    def finished as bool init kindAt($d, "/finished") == "string";
    return GuestProcess{pid: $pid, finished: $finished, exitCode: number($d, "/exit_code")};
}

/**
 * Wait until a guest process ends, asking every `pollMs`; a network
 * failure or a 5xx answer is retried.
 *
 * @param c {Client} the client
 * @param vm {string} the VM id
 * @param creds {GuestCredentials} the guest account
 * @param pid {int} the process id
 * @param timeoutMs {int} how long to wait; 0 waits for ever
 * @return {GuestProcess} the finished process
 * @throws {VmwareError} kind `"vmware"` when the time runs out, after
 *   `MAX_POLL_FAILURES` failed checks in a row, or on a 4xx answer
 */
export func waitGuestProcess(
    c as Client,
    vm as string,
    creds as GuestCredentials,
    pid as int,
    timeoutMs as int) {
    def started as time.Time init time.now();
    def failures as int init 0;
    while (true) {
        def p as GuestProcess;
        def answered as bool init true;
        try {
            $p = guestProcess($c, $vm, $creds, $pid);
        } catch (e) {
            $answered = false;
            # only the deck's own failures can be retried; a cap, a
            # cancellation or a fault passes on at once
            if ($e.kind != ERROR_KIND) {
                throw $e;
            }
            $failures = retryOrThrow($e, $failures);
        }
        if ($answered) {
            if ($p.finished) {
                return $p;
            }
            $failures = 0;
        }
        def waited as int init time.milliseconds(time.sub(time.now(), $started));
        if ($timeoutMs > 0 and $waited >= $timeoutMs) {
            fail("guest process " + convert.toString($pid) + " still running after " +
                convert.toString($timeoutMs) + " ms");
        }
        time.sleep(time.fromMilliseconds(pollDelay($c)));
    }
}

/**
 * The pause between two status checks. A client built without `client` has
 * `pollMs` 0, which would ask without pause; it waits a second instead.
 *
 * @param c {Client} the client
 * @return {int} milliseconds, at least 1
 */
func pollDelay(c as Client) {
    if ($c.pollMs <= 0) {
        return 1000;
    }
    return $c.pollMs;
}

/**
 * Whether an address is loopback or link-local, so useless from outside the
 * guest.
 *
 * @param ip {string} an IPv4 or IPv6 address, without prefix
 * @return {bool} true for 127.0.0.0/8, 169.254.0.0/16, ::1 and fe80::/10
 */
func isLocalAddress(ip as string) {
    def low as string init strings.lower($ip);
    for (def prefix in ["127.", "169.254.", "fe8", "fe9", "fea", "feb"]) {
        if (strings.startsWith($low, $prefix)) {
            return true;
        }
    }
    return $low == "::1";
}

/**
 * Count a failed status check, or give up. A 4xx answer is final (an ended
 * session does not heal by waiting); a network failure or a 5xx answer is
 * retried up to `MAX_POLL_FAILURES` times in a row.
 *
 * @param e {VmwareError} the failure
 * @param failures {int} failures in a row so far
 * @return {int} the new count
 * @throws {VmwareError} the failure itself, when it is final
 */
func retryOrThrow(e as VmwareError, failures as int) {
    if ($e.status >= 400 and $e.status <= 499) {
        throw $e;
    }
    if ($failures + 1 >= MAX_POLL_FAILURES) {
        throw $e;
    }
    return $failures + 1;
}

/**
 * Keep a session alive: check it (which also restarts vCenter's idle
 * timer) and log in again only when it has ended. Call it before each batch
 * of work in a long-running program.
 *
 * @param c {Client} the client, with or without a session
 * @param username {string} the user to log in as when needed
 * @param password {string} its password
 * @return {Client} the client with a working session
 * @throws {VmwareError} kind `"vmware"` when the check fails for another reason
 *   than an ended session, or the login is refused
 */
export func ensureSession(c as Client, username as string, password as string) {
    if ($c.session == "") {
        return login($c, $username, $password);
    }
    try {
        get($c, "/api/session");
    } catch (e) {
        # only an ended session (401) means log in again
        if ($e.kind != ERROR_KIND or $e.status != 401) {
            throw $e;
        }
        return login($c, $username, $password);
    }
    return $c;
}

/**
 * A one-line description of a client for logs, without its session id.
 * Print this, never the `Client` itself.
 *
 * @param c {Client} the client
 * @return {string} e.g. `https://vc.example.com (session)`
 */
export func describe(c as Client) {
    def who as string init "no session";
    if ($c.session != "") {
        $who = "session";
    }
    if ($c.tls.skipVerify) {
        $who = $who + ", certificate not checked";
    }
    return $c.url + " (" + $who + ")";
}
