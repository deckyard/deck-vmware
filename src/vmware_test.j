# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for vmware: jennifer test src/vmware_test.j
 *
 * The parsing and checking helpers are tested directly. The requests go to an
 * `httpd` server on a loopback port that answers with canned vCenter replies
 * and hands back what it received.
 */
use httpd;
use task;
use testing;

/** A canned reply. */
def struct Reply {
    status as int,
    body as string
};

/** One request as the fake server saw it. */
def struct Seen {
    method as string,
    path as string,
    query as string,
    auth as string,
    session as string,
    contentType as string,
    body as string
};

/** A running fake server. */
def struct Fake {
    srv as httpd.Server,
    url as string,
    t as task of list of Seen
};

/**
 * Mark a call that should have thrown. The error reaches the test's own
 * `catch`, whose assertions on kind and message then fail.
 *
 * @param what {string} what got through
 * @throws {Error} always, with `kind` `"missed"`
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * The query parameters the tests send, as `key=value&...` in a fixed order.
 * Not `httpd.rawQuery`: 0.25.0 does not have it. A repeated key shows
 * its first value only.
 *
 * @param req {httpd.Request} the request
 * @return {string} the parameters that are set
 */
func queryOf(req as httpd.Request) {
    def parts as list of string init [];
    for (def key in ["action", "names", "power_states", "clusters", "type", "vmw-task"]) {
        def value as string init httpd.query($req, $key);
        if ($value != "") {
            $parts[] = $key + "=" + $value;
        }
    }
    return strings.join($parts, "&");
}

/**
 * Answer one request per reply, in order.
 *
 * @param srv {httpd.Server} the listening server
 * @param replies {list of Reply} the replies
 * @return {list of Seen} the requests
 */
func serve(srv as httpd.Server, replies as list of Reply) {
    def seen as list of Seen init [];
    for (def r in $replies) {
        def req as httpd.Request init httpd.accept($srv);
        $seen[] = Seen{
            method: httpd.method($req),
            path: httpd.path($req),
            query: queryOf($req),
            auth: httpd.header($req, "Authorization"),
            session: httpd.header($req, SESSION_HEADER),
            contentType: httpd.header($req, "Content-Type"),
            body: convert.stringFromBytes(httpd.body($req), "utf-8")
        };
        httpd.respond($req, $r.status, $r.body);
    }
    return $seen;
}

/**
 * Start a fake server that gives these replies.
 *
 * @param replies {list of Reply} the replies
 * @return {Fake} the server
 */
func fake(replies as list of Reply) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of Seen init spawn {
        return serve($srv, $replies);
    };
    return Fake{srv: $srv, url: "http://" + httpd.address($srv), t: $t};
}

/**
 * Stop a fake server.
 *
 * @param f {Fake} the server
 * @return {list of Seen} what it received
 */
func finish(f as Fake) {
    def seen as list of Seen init task.wait($f.t);
    httpd.shutdown($f.srv);
    return $seen;
}

/**
 * A 200 reply.
 *
 * @param body {string} the JSON
 * @return {Reply} the reply
 */
func ok(body as string) {
    return Reply{status: 200, body: $body};
}

/**
 * A 204 reply, as power actions get.
 *
 * @return {Reply} the reply
 */
func empty() {
    return Reply{status: 204, body: ""};
}

/**
 * A client with a session, for a fake server.
 *
 * @param f {Fake} the server
 * @return {Client} the client
 */
func sessionClient(f as Fake) {
    return withSession(client($f.url), "b00db39f948d13ea1e59b814e6e1ed4e");
}

func emptyHost() {
    client(" ");
}

func pathWithoutSlash() {
    ensurePath("api/vcenter/vm");
}

func pathUp() {
    ensurePath("/api/../rest");
}

func pathTwoQueries() {
    ensurePath("/api/vcenter/vm?a=1?b=2");
}

func traceMethod() {
    call(client("vc"), "TRACE", "/api", json.decode("null"));
}

func emptyId() {
    segment(" ");
}

func logoutWithoutSession() {
    logout(client("vc"));
}

func unreachable() {
    get(withTimeout(client("http://127.0.0.1:1"), 2000), "/api/vcenter/vm");
}

func testBaseUrl() {
    testing.assertEqual(baseUrl("vcenter.example.com"), "https://vcenter.example.com");
    testing.assertEqual(baseUrl("10.0.0.5:8443"), "https://10.0.0.5:8443");
    testing.assertEqual(baseUrl("https://vc/"), "https://vc");
    testing.assertEqual(baseUrl("https://vc/api/"), "https://vc");
    testing.assertEqual(baseUrl("http://127.0.0.1:9"), "http://127.0.0.1:9");
    testing.assertThrows("emptyHost", ERROR_KIND);
}

func testBuilders() {
    def c as Client init client("vc");
    testing.assertEqual($c.session, "");
    testing.assertEqual(withInsecure($c).tls.skipVerify, true);
    def pem as bytes init convert.bytesFromString("-----BEGIN CERTIFICATE-----", "utf-8");
    def trusted as Client init withCaCert(withInsecure($c), $pem);
    testing.assertEqual($trusted.tls.skipVerify, false);
    testing.assertEqual($trusted.tls.caCert, $pem);
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withRetries($c, 3).retries, 3);
    testing.assertEqual(withSession($c, "s1").session, "s1");
}

func testQuery() {
    testing.assertEqual(query({}), "");
    testing.assertEqual(query({"names": []}), "");
    testing.assertEqual(
        query({"names": ["web 1", "db&2"], "type": ["VIRTUAL_MACHINE"]}),
        "?names=web+1&names=db%262&type=VIRTUAL_MACHINE");
    def f as VmFilter;
    testing.assertEqual(vmQuery($f), "");
    $f.powerStates = [POWERED_ON, SUSPENDED];
    $f.resourcePools = ["resgroup-9"];
    testing.assertEqual(
        vmQuery($f),
        "?power_states=POWERED_ON&power_states=SUSPENDED&resource_pools=resgroup-9");
}

func testPathsAreChecked() {
    ensurePath("/api/vcenter/vm?names=web");
    testing.assertThrows("pathWithoutSlash", ERROR_KIND);
    testing.assertThrows("pathUp", ERROR_KIND);
    testing.assertThrows("pathTwoQueries", ERROR_KIND);
    testing.assertThrows("traceMethod", ERROR_KIND);
    testing.assertEqual(segment("vm-42"), "vm-42");
    testing.assertEqual(segment("a/b"), "a%2Fb");
    testing.assertThrows("emptyId", ERROR_KIND);
}

func testFailureText() {
    def r as http.Response;
    $r.status = 404;
    $r.body = '{"error_type":"NOT_FOUND","messages":[{"args":["vm-9"],' +
        '"default_message":"Virtual machine with identifier vm-9 does not exist.","id":"x"}]}';
    testing.assertEqual(
        failureText($r),
        "HTTP 404 NOT_FOUND: Virtual machine with identifier vm-9 does not exist.");
    $r.status = 400;
    $r.body = '{"type":"com.vmware.vapi.std.errors.already_in_desired_state",' +
        '"value":{"messages":[{"default_message":"Virtual machine is already powered on."},' +
        '{"default_message":"Nothing to do."}]}}';
    testing.assertEqual(
        failureText($r),
        "HTTP 400 ALREADY_IN_DESIRED_STATE: Virtual machine is already powered on. Nothing to do.");
    $r.status = 401;
    $r.body = '{"error_type":"UNAUTHENTICATED","messages":[]}';
    testing.assertEqual(failureText($r), "HTTP 401 UNAUTHENTICATED");
    $r.status = 502;
    $r.statusText = "Bad Gateway";
    $r.body = "<html>proxy</html>";
    testing.assertEqual(failureText($r), "HTTP 502: Bad Gateway");
    $r.statusText = "";
    testing.assertEqual(failureText($r), "HTTP 502");
}

func testReaders() {
    def d as json.Value init json.decode('{"s":"x","i":3,"f":2.5,"b":true,"n":null}');
    testing.assertEqual(field($d, "/s"), "x");
    testing.assertEqual(field($d, "/i"), "3");
    testing.assertEqual(field($d, "/b"), "");
    testing.assertEqual(field($d, "/missing"), "");
    testing.assertEqual(number($d, "/f"), 2);
    testing.assertEqual(number($d, "/s"), 0);
    testing.assertEqual(flag($d, "/b"), true);
    testing.assertEqual(flag($d, "/i"), false);
    testing.assertEqual(kindAt($d, "/missing/deeper"), "missing");
    testing.assertEqual(json.typeOf(getAt($d, "/missing")), "null");
    testing.assertEqual(items($d), []);
}

func testLoginAndLogout() {
    def f as Fake init fake([
        Reply{status: 201, body: '"b00db39f"'},
        ok('{"version":"8.0.2.00100"}'),
        empty()
    ]);
    def c as Client init login(client($f.url), "administrator@vsphere.local", "s3cret!");
    testing.assertEqual($c.session, "b00db39f");
    def v as Version init version($c);
    $c = logout($c);
    def seen as list of Seen init finish($f);
    testing.assertEqual($c.session, "");
    testing.assertEqual($v.version, "8.0.2.00100");
    testing.assertEqual($seen[0].method, "POST");
    testing.assertEqual($seen[0].path, "/api/session");
    testing.assertEqual($seen[0].auth, http.basic("administrator@vsphere.local", "s3cret!"));
    testing.assertEqual($seen[0].session, "");
    testing.assertEqual($seen[1].path, "/api/appliance/system/version");
    testing.assertEqual($seen[1].session, "b00db39f");
    testing.assertEqual($seen[1].auth, "");
    testing.assertEqual($seen[2].method, "DELETE");
    testing.assertEqual($seen[2].path, "/api/session");
    testing.assertThrows("logoutWithoutSession", ERROR_KIND);
}

func testARefusedLogin() {
    def f as Fake init fake([
        Reply{status: 401, body: '{"error_type":"UNAUTHENTICATED","messages":[]}'},
        ok('{}')
    ]);
    try {
        login(client($f.url), "ada", "wrong");
        missed("a refused login passed");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
        testing.assertEqual($e.message, "vmware: POST /api/session: HTTP 401 UNAUTHENTICATED");
    }
    try {
        login(client($f.url), "ada", "pw");
        missed("a login without a session id passed");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: the login reply holds no session id");
    }
    finish($f);
}

func testGenericVerbs() {
    def f as Fake init fake([
        ok('"urn:vmomi:InventoryServiceTag:1"'),
        empty(),
        empty(),
        empty(),
        Reply{status: 200, body: "not json"}
    ]);
    def c as Client init sessionClient($f);
    def body as json.Value init json.decode('{"name":"backup","category_id":"urn:c:1"}');
    def id as json.Value init post($c, "/api/cis/tagging/tag", $body);
    testing.assertEqual(
        json.typeOf(patch($c, "/api/cis/tagging/tag/t1", json.decode('{"name":"b2"}'))),
        "null");
    put($c, "/api/vcenter/vm/vm-42/hardware/memory", json.decode("null"));
    delete($c, "/api/cis/tagging/tag/t1");
    try {
        call($c, "get", "/api/vcenter/vm", json.decode("null"));
        missed("a reply that is not JSON passed");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: GET /api/vcenter/vm: the reply is not JSON");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual(json.asString($id), "urn:vmomi:InventoryServiceTag:1");
    testing.assertEqual($seen[0].contentType, "application/json");
    testing.assertEqual(json.decode($seen[0].body), $body);
    testing.assertEqual($seen[1].method, "PATCH");
    testing.assertEqual($seen[2].method, "PUT");
    testing.assertEqual($seen[2].body, "");
    testing.assertEqual($seen[2].contentType, "");
    testing.assertEqual($seen[3].method, "DELETE");
    testing.assertEqual($seen[3].path, "/api/cis/tagging/tag/t1");
    testing.assertEqual($seen[4].method, "GET");
    testing.assertThrows("unreachable", ERROR_KIND);
}

func testVms() {
    def f as Fake init fake([
        ok(
            '[{"vm":"vm-42","name":"web","power_state":"POWERED_ON",' +
                '"cpu_count":2,"memory_size_MiB":4096},' +
                '{"vm":"vm-43","name":"db","power_state":"POWERED_OFF"}]')
    ]);
    def filter as VmFilter;
    $filter.names = ["web", "db"];
    $filter.clusters = ["domain-c8"];
    def all as list of VmSummary init vms(sessionClient($f), $filter);
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/vcenter/vm");
    testing.assertEqual($seen[0].query, "names=web&clusters=domain-c8");
    testing.assertEqual(len($all), 2);
    testing.assertEqual(
        $all[0],
        VmSummary{vm: "vm-42", name: "web", powerState: POWERED_ON, cpuCount: 2, memoryMiB: 4096});
    testing.assertEqual($all[1].powerState, POWERED_OFF);
    testing.assertEqual($all[1].cpuCount, 0);
}

func testVmByName() {
    def one as string init '[{"vm":"vm-42","name":"web","power_state":"POWERED_ON"}]';
    def two as string init '[{"vm":"vm-42","name":"web"},{"vm":"vm-77","name":"web"}]';
    def f as Fake init fake([ok($one), ok("[]"), ok($two)]);
    def c as Client init sessionClient($f);
    testing.assertEqual(vmByName($c, "web").vm, "vm-42");
    try {
        vmByName($c, "ghost");
        missed("a missing VM was found");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: no VM named \"ghost\"");
    }
    try {
        vmByName($c, "web");
        missed("two VMs passed as one");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: 2 VMs are named \"web\"");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[1].query, "names=ghost");
}

func testVmDetailAndPower() {
    def f as Fake init fake([
        ok('{"name":"web","guest_OS":"UBUNTU_64","cpu":{"count":2},"memory":{"size_MiB":4096}}'),
        ok('{"state":"POWERED_OFF"}'),
        empty(),
        empty(),
        empty(),
        empty(),
        empty(),
        empty()
    ]);
    def c as Client init sessionClient($f);
    def d as json.Value init vm($c, "vm-42");
    def state as string init powerState($c, "vm-42");
    powerOn($c, "vm-42");
    powerOff($c, "vm-42");
    suspend($c, "vm-42");
    reset($c, "vm-42");
    shutdownGuest($c, "vm-42");
    rebootGuest($c, "vm-42");
    def seen as list of Seen init finish($f);
    testing.assertEqual(json.asInt($d, "/memory/size_MiB"), 4096);
    testing.assertEqual($state, POWERED_OFF);
    testing.assertEqual($seen[0].path, "/api/vcenter/vm/vm-42");
    testing.assertEqual($seen[1].path, "/api/vcenter/vm/vm-42/power");
    def calls as list of string init [];
    for (def s in lists.slice($seen, 2)) {
        testing.assertEqual($s.method, "POST");
        $calls[] = $s.path + "?" + $s.query;
    }
    testing.assertEqual(
        $calls,
        [
            "/api/vcenter/vm/vm-42/power?action=start",
            "/api/vcenter/vm/vm-42/power?action=stop",
            "/api/vcenter/vm/vm-42/power?action=suspend",
            "/api/vcenter/vm/vm-42/power?action=reset",
            "/api/vcenter/vm/vm-42/guest/power?action=shutdown",
            "/api/vcenter/vm/vm-42/guest/power?action=reboot"
        ]);
}

func testGuestIdentity() {
    def f as Fake init fake([
        ok('{"name":"UBUNTU_64","family":"LINUX",' +
            '"full_name":{"args":[],"default_message":"Ubuntu Linux (64-bit)",' +
            '"id":"vmsg.guestos.ubuntu64Guest.label"},' +
            '"host_name":"web01","ip_address":"10.0.0.42"}'),
        Reply{
            status: 503,
            body: '{"error_type":"SERVICE_UNAVAILABLE",' +
                '"messages":[{"default_message":"Tools not running."}]}'
        }
    ]);
    def c as Client init sessionClient($f);
    def g as GuestIdentity init guestIdentity($c, "vm-42");
    try {
        guestIdentity($c, "vm-43");
        missed("an identity without Tools passed");
    } catch (e) {
        testing.assertTrue(strings.contains(
            $e.message,
            "HTTP 503 SERVICE_UNAVAILABLE: Tools not running."));
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($g.fullName, "Ubuntu Linux (64-bit)");
    testing.assertEqual($g.hostName, "web01");
    testing.assertEqual($g.ipAddress, "10.0.0.42");
    testing.assertEqual($g.family, "LINUX");
    testing.assertEqual($seen[0].path, "/api/vcenter/vm/vm-42/guest/identity");
}

func testInventory() {
    def f as Fake init fake([
        ok('[{"host":"host-12","name":"esx1.lab","connection_state":"CONNECTED",' +
            '"power_state":"POWERED_ON"}]'),
        ok('[{"cluster":"domain-c8","name":"Lab","ha_enabled":true,"drs_enabled":false}]'),
        ok('[{"datastore":"datastore-15","name":"nvme","type":"VMFS","capacity":1099511627776,' +
            '"free_space":549755813888}]'),
        ok('[{"datacenter":"datacenter-3","name":"DC1"}]'),
        ok('[{"network":"network-17","name":"VM Network","type":"STANDARD_PORTGROUP"}]'),
        ok('[{"folder":"group-v4","name":"vm","type":"VIRTUAL_MACHINE"}]'),
        ok('[{"folder":"group-h5","name":"host","type":"HOST"}]'),
        ok('[{"resource_pool":"resgroup-9","name":"Resources"}]')
    ]);
    def c as Client init sessionClient($f);
    def hs as list of Host init hosts($c);
    def cs as list of Cluster init clusters($c);
    def ds as list of Datastore init datastores($c);
    def dcs as list of Item init datacenters($c);
    def ns as list of Item init networks($c);
    def vmFolders as list of Item init folders($c, "VIRTUAL_MACHINE");
    def allFolders as list of Item init folders($c, "");
    def pools as list of Item init resourcePools($c);
    def seen as list of Seen init finish($f);
    testing.assertEqual(
        $hs[0],
        Host{
            host: "host-12",
            name: "esx1.lab",
            connectionState: "CONNECTED",
            powerState: POWERED_ON
        });
    testing.assertEqual($cs[0].haEnabled, true);
    testing.assertEqual($cs[0].drsEnabled, false);
    testing.assertEqual($ds[0].capacity, 1099511627776);
    testing.assertEqual($ds[0].freeSpace, 549755813888);
    testing.assertEqual($dcs[0], Item{id: "datacenter-3", name: "DC1", type: ""});
    testing.assertEqual($ns[0].type, "STANDARD_PORTGROUP");
    testing.assertEqual($vmFolders[0].id, "group-v4");
    testing.assertEqual($allFolders[0].type, "HOST");
    testing.assertEqual($pools[0].id, "resgroup-9");
    def paths as list of string init [];
    for (def s in $seen) {
        $paths[] = $s.path;
    }
    testing.assertEqual(
        $paths,
        [
            "/api/vcenter/host",
            "/api/vcenter/cluster",
            "/api/vcenter/datastore",
            "/api/vcenter/datacenter",
            "/api/vcenter/network",
            "/api/vcenter/folder",
            "/api/vcenter/folder",
            "/api/vcenter/resource-pool"
        ]);
    testing.assertEqual($seen[5].query, "type=VIRTUAL_MACHINE");
    testing.assertEqual($seen[6].query, "");
}

func specWithoutGuestOs() {
    def s as VmSpec;
    $s.name = "web";
    createSpec($s);
}

func testCreateSpec() {
    def s as VmSpec;
    $s.name = "web5";
    $s.guestOs = "UBUNTU_64";
    $s.placement.folder = "group-v4";
    $s.placement.cluster = "domain-c8";
    $s.placement.datastore = "datastore-15";
    def bare as json.Value init createSpec($s);
    testing.assertEqual(json.keys($bare), ["name", "guest_OS", "placement"]);
    testing.assertEqual(json.keys($bare, "/placement"), ["folder", "cluster", "datastore"]);
    $s.cpuCount = 2;
    $s.memoryMiB = 4096;
    $s.diskGiB = 40;
    $s.network = "dvportgroup-21";
    $s.networkType = "DISTRIBUTED_PORTGROUP";
    def full as json.Value init createSpec($s);
    testing.assertEqual(json.asInt($full, "/cpu/count"), 2);
    testing.assertEqual(json.asInt($full, "/memory/size_MiB"), 4096);
    testing.assertEqual(json.asInt($full, "/disks/0/new_vmdk/capacity"), 42949672960);
    testing.assertEqual(json.asString($full, "/nics/0/backing/type"), "DISTRIBUTED_PORTGROUP");
    testing.assertEqual(json.asString($full, "/nics/0/backing/network"), "dvportgroup-21");
    testing.assertEqual(json.asBool($full, "/nics/0/start_connected"), true);
    $s.networkType = "";
    testing.assertEqual(
        json.asString(createSpec($s), "/nics/0/backing/type"),
        "STANDARD_PORTGROUP");
    testing.assertThrows("specWithoutGuestOs", ERROR_KIND);
}

func testCreateCloneDeployDelete() {
    def f as Fake init fake([
        ok('"vm-101"'),
        ok('"vm-102"'),
        ok('["urn:item:1"]'),
        ok('"vm-103"'),
        empty(),
        ok("null")
    ]);
    def c as Client init sessionClient($f);
    def s as VmSpec;
    $s.name = "web5";
    $s.guestOs = "UBUNTU_64";
    $s.placement.folder = "group-v4";
    testing.assertEqual(createVm($c, $s), "vm-101");
    def p as Placement;
    $p.resourcePool = "resgroup-9";
    $p.datastore = "datastore-15";
    testing.assertEqual(cloneVm($c, "vm-42", "web6", $p, true), "vm-102");
    def item as string init findLibraryItem($c, "ubuntu-24.04");
    testing.assertEqual(deployTemplate($c, $item, "web7", $p, false), "vm-103");
    deleteVm($c, "vm-101");
    try {
        createVmFrom($c, createSpec($s));
        missed("a create without an id passed");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: createVm returned no id");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/vcenter/vm");
    testing.assertEqual(json.asString(json.decode($seen[0].body), "/placement/folder"), "group-v4");
    testing.assertEqual($seen[1].query, "action=clone");
    def clone as json.Value init json.decode($seen[1].body);
    testing.assertEqual(json.asString($clone, "/source"), "vm-42");
    testing.assertEqual(json.asString($clone, "/placement/datastore"), "datastore-15");
    testing.assertEqual(json.asBool($clone, "/power_on"), true);
    testing.assertEqual($seen[2].path, "/api/content/library/item");
    testing.assertEqual($seen[2].query, "action=find");
    testing.assertEqual(json.asString(json.decode($seen[2].body), "/name"), "ubuntu-24.04");
    testing.assertEqual($seen[3].path, "/api/vcenter/vm-template/library-items/urn:item:1");
    def deploy as json.Value init json.decode($seen[3].body);
    testing.assertEqual(json.has($deploy, "/placement/datastore"), false);
    testing.assertEqual(json.asString($deploy, "/placement/resource_pool"), "resgroup-9");
    testing.assertEqual(json.asString($deploy, "/disk_storage/datastore"), "datastore-15");
    testing.assertEqual(json.asBool($deploy, "/powered_on"), false);
    testing.assertEqual($seen[4].method, "DELETE");
    testing.assertEqual($seen[4].path, "/api/vcenter/vm/vm-101");
}

func testFindLibraryItemNeedsOneMatch() {
    def f as Fake init fake([ok("[]"), ok('["a","b"]')]);
    def c as Client init sessionClient($f);
    try {
        findLibraryItem($c, "ghost");
        missed("a missing item was found");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: no library item named \"ghost\"");
    }
    try {
        findLibraryItem($c, "twin");
        missed("two items passed as one");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: 2 library items are named \"twin\"");
    }
    finish($f);
}

func linuxWithoutDomain() {
    def lc as LinuxCustomization;
    $lc.hostName = "web08";
    linuxSpec($lc);
}

func badCardinality() {
    createCategory(client("vc"), "env", "SOME");
}

/**
 * Guest credentials for the tests.
 *
 * @return {GuestCredentials} root and a password
 */
func rootLogin() {
    return GuestCredentials{user: "root", password: "pw"};
}

func testTasks() {
    def f as Fake init fake([
        ok('"task-77"'),
        ok('{"status":"RUNNING","description":{"default_message":"Clone VM"},' +
            '"progress":{"total":200,"completed":50}}'),
        ok('{"status":"RUNNING","progress":{"total":100,"completed":90}}'),
        ok('{"status":"SUCCEEDED","result":"vm-110","progress":{"total":100,"completed":100}}'),
        ok('{"status":"FAILED","error":{"error_type":"NOT_FOUND",' +
            '"messages":[{"default_message":"No VM."}]}}'),
        ok('{"status":"SUCCEEDED","result":{"a":1}}'),
        ok('"task-78"'),
        ok('{"status":"RUNNING"}'),
        ok('{"status":"RUNNING"}')
    ]);
    def c as Client init withPollInterval(sessionClient($f), 1);
    def p as Placement;
    def id as string init cloneVmTask($c, "vm-42", "web8", $p, false);
    def now as Task init taskStatus($c, $id);
    def done as Task init waitTask($c, $id, 0);
    def failed as Task init taskStatus($c, $id);
    def other as Task init taskStatus($c, $id);
    def deploy as string init startTask(
        $c,
        "POST",
        "/api/vcenter/ovf/library-item/urn:item:9?action=deploy",
        json.map());
    try {
        waitTask(withPollInterval($c, 30), $id, 20);
        missed("waitTask did not give up");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "still RUNNING after 20 ms"));
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($id, "task-77");
    testing.assertEqual($seen[0].path, "/api/vcenter/vm");
    testing.assertEqual($seen[0].query, "action=clone&vmw-task=true");
    testing.assertEqual(json.asString(json.decode($seen[0].body), "/source"), "vm-42");
    testing.assertEqual($seen[1].path, "/api/cis/tasks/task-77");
    testing.assertEqual(
        $now,
        Task{
            id: "task-77",
            status: "RUNNING",
            description: "Clone VM",
            progress: 25,
            result: "",
            error: ""
        });
    testing.assertEqual($done.status, "SUCCEEDED");
    testing.assertEqual($done.result, "vm-110");
    testing.assertEqual($failed.error, "NOT_FOUND: No VM.");
    testing.assertEqual($other.result, '{"a":1}');
    testing.assertEqual($deploy, "task-78");
    testing.assertEqual($seen[6].path, "/api/vcenter/ovf/library-item/urn:item:9");
    testing.assertEqual($seen[6].query, "action=deploy&vmw-task=true");
    testing.assertEqual(taskPath("/api/x"), "/api/x?vmw-task=true");
}

func testCustomization() {
    def lc as LinuxCustomization;
    $lc.hostName = "web08";
    $lc.domain = "lab.example";
    def dhcp as json.Value init linuxSpec($lc);
    testing.assertEqual(
        json.asString($dhcp, "/configuration_spec/linux_config/hostname/fixed_name"),
        "web08");
    testing.assertEqual(
        json.asString($dhcp, "/configuration_spec/linux_config/hostname/type"),
        "FIXED");
    testing.assertEqual(json.has($dhcp, "/configuration_spec/linux_config/time_zone"), false);
    testing.assertEqual(json.asString($dhcp, "/interfaces/0/adapter/ipv4/type"), "DHCP");
    $lc.ipAddress = "10.0.0.8";
    $lc.prefix = 24;
    $lc.gateway = "10.0.0.1";
    $lc.timeZone = "Europe/Vienna";
    $lc.dnsServers = ["10.0.0.1"];
    $lc.dnsSuffixes = ["lab.example"];
    def fixed as json.Value init linuxSpec($lc);
    testing.assertEqual(json.asString($fixed, "/interfaces/0/adapter/ipv4/type"), "STATIC");
    testing.assertEqual(json.asInt($fixed, "/interfaces/0/adapter/ipv4/prefix"), 24);
    testing.assertEqual(json.asString($fixed, "/interfaces/0/adapter/ipv4/gateways/0"), "10.0.0.1");
    testing.assertEqual(json.asString($fixed, "/global_DNS_settings/dns_servers/0"), "10.0.0.1");
    testing.assertEqual(
        json.asString($fixed, "/configuration_spec/linux_config/time_zone"),
        "Europe/Vienna");
    testing.assertThrows("linuxWithoutDomain", ERROR_KIND);
    def f as Fake init fake([
        ok('[{"name":"linux-dhcp","description":"","os_type":"LINUX",' +
            '"last_modified":"2026-01-01T00:00:00Z"}]'),
        empty(),
        empty(),
        empty()
    ]);
    def c as Client init sessionClient($f);
    def specs as list of Item init customizationSpecs($c);
    customize($c, "vm-42", "linux-dhcp");
    customizeLinux($c, "vm-42", $lc);
    customizeWith(
        $c,
        "vm-43",
        json.set($fixed, "/configuration_spec/linux_config/script_text", "#!/bin/sh"));
    def seen as list of Seen init finish($f);
    testing.assertEqual($specs[0], Item{id: "linux-dhcp", name: "linux-dhcp", type: "LINUX"});
    testing.assertEqual($seen[0].path, "/api/vcenter/guest/customization-specs");
    testing.assertEqual($seen[1].method, "PUT");
    testing.assertEqual($seen[1].path, "/api/vcenter/vm/vm-42/guest/customization");
    testing.assertEqual($seen[1].body, '{"name":"linux-dhcp"}');
    testing.assertEqual(json.decode($seen[2].body), json.set(json.map(), "/spec", $fixed));
    testing.assertEqual($seen[3].path, "/api/vcenter/vm/vm-43/guest/customization");
    testing.assertEqual(
        json.asString(
            json.decode($seen[3].body),
            "/spec/configuration_spec/linux_config/script_text"),
        "#!/bin/sh");
}

func testHardware() {
    def f as Fake init fake([
        empty(),
        empty(),
        ok('[{"disk":"2000"},{"disk":"2001"}]'),
        ok('{"label":"Hard disk 1","type":"SCSI","capacity":42949672960,' +
            '"backing":{"type":"VMDK_FILE","vmdk_file":"[nvme] web/web.vmdk"}}'),
        ok('{"label":"Hard disk 2","type":"SCSI","capacity":10737418240}'),
        ok('"2002"'),
        empty(),
        ok('[{"nic":"4000"}]'),
        ok('{"label":"Network adapter 1","type":"VMXNET3","mac_address":"00:50:56:aa:bb:cc",' +
            '"state":"CONNECTED","start_connected":true,' +
            '"backing":{"type":"DISTRIBUTED_PORTGROUP","network":"dvportgroup-21"}}'),
        ok('"4001"'),
        empty(),
        empty(),
        empty()
    ]);
    def c as Client init sessionClient($f);
    setCpu($c, "vm-42", 4);
    setMemory($c, "vm-42", 8192);
    def ds as list of Disk init disks($c, "vm-42");
    testing.assertEqual(addDisk($c, "vm-42", 20), "2002");
    removeDisk($c, "vm-42", "2001");
    def ns as list of Nic init nics($c, "vm-42");
    testing.assertEqual(addNic($c, "vm-42", "network-17", ""), "4001");
    connectNic($c, "vm-42", "4001");
    disconnectNic($c, "vm-42", "4001");
    removeNic($c, "vm-42", "4001");
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "PATCH");
    testing.assertEqual($seen[0].path, "/api/vcenter/vm/vm-42/hardware/cpu");
    testing.assertEqual($seen[0].body, '{"count":4}');
    testing.assertEqual($seen[1].body, '{"size_MiB":8192}');
    testing.assertEqual(
        $ds[0],
        Disk{
            disk: "2000",
            label: "Hard disk 1",
            type: "SCSI",
            capacity: 42949672960,
            file: "[nvme] web/web.vmdk"
        });
    testing.assertEqual($ds[1].file, "");
    testing.assertEqual($seen[4].path, "/api/vcenter/vm/vm-42/hardware/disk/2001");
    testing.assertEqual(json.asInt(json.decode($seen[5].body), "/new_vmdk/capacity"), 21474836480);
    testing.assertEqual($seen[6].method, "DELETE");
    testing.assertEqual($ns[0].networkType, "DISTRIBUTED_PORTGROUP");
    testing.assertEqual($ns[0].startConnected, true);
    testing.assertEqual($ns[0].macAddress, "00:50:56:aa:bb:cc");
    def nic as json.Value init json.decode($seen[9].body);
    testing.assertEqual(json.asString($nic, "/backing/type"), "STANDARD_PORTGROUP");
    testing.assertEqual(json.asString($nic, "/type"), "VMXNET3");
    testing.assertEqual(
        $seen[10].path + "?" + $seen[10].query,
        "/api/vcenter/vm/vm-42/hardware/ethernet/4001?action=connect");
    testing.assertEqual($seen[11].query, "action=disconnect");
    testing.assertEqual($seen[12].method, "DELETE");
}

func testTags() {
    def f as Fake init fake([
        ok('["urn:c:1"]'),
        ok('{"name":"env","description":"stage","cardinality":"SINGLE","associable_types":[]}'),
        ok('["urn:t:1"]'),
        ok('{"name":"prod","description":"","category_id":"urn:c:1"}'),
        ok('"urn:c:2"'),
        ok('"urn:t:2"'),
        empty(),
        empty(),
        ok('["urn:t:1","urn:t:2"]'),
        ok('[{"id":"vm-42","type":"VirtualMachine"},{"id":"host-12","type":"HostSystem"}]'),
        empty(),
        empty()
    ]);
    def c as Client init sessionClient($f);
    def cs as list of Category init categories($c);
    def ts as list of Tag init tags($c);
    def cat as string init createCategory($c, "owner", "MULTIPLE");
    def tag as string init createTag($c, $cat, "team-a");
    attachTag($c, $tag, "vm-42");
    detachTag($c, $tag, "vm-42");
    def onVm as list of string init vmTags($c, "vm-42");
    def vms as list of string init taggedVms($c, "urn:t:1");
    deleteTag($c, $tag);
    deleteCategory($c, $cat);
    def seen as list of Seen init finish($f);
    testing.assertEqual(
        $cs[0],
        Category{id: "urn:c:1", name: "env", description: "stage", cardinality: "SINGLE"});
    testing.assertEqual(
        $ts[0],
        Tag{id: "urn:t:1", name: "prod", description: "", categoryId: "urn:c:1"});
    testing.assertEqual($seen[1].path, "/api/cis/tagging/category/urn:c:1");
    def newCat as json.Value init json.decode($seen[4].body);
    testing.assertEqual(json.asString($newCat, "/cardinality"), "MULTIPLE");
    testing.assertEqual(json.length($newCat, "/associable_types"), 0);
    testing.assertEqual(json.asString(json.decode($seen[5].body), "/category_id"), "urn:c:2");
    testing.assertEqual($seen[6].path, "/api/cis/tagging/tag-association/urn:t:2");
    testing.assertEqual($seen[6].query, "action=attach");
    testing.assertEqual($seen[6].body, '{"object_id":{"id":"vm-42","type":"VirtualMachine"}}');
    testing.assertEqual($seen[7].query, "action=detach");
    testing.assertEqual($seen[8].path, "/api/cis/tagging/tag-association");
    testing.assertEqual($seen[8].query, "action=list-attached-tags");
    testing.assertEqual($onVm, ["urn:t:1", "urn:t:2"]);
    testing.assertEqual($seen[9].query, "action=list-attached-objects");
    testing.assertEqual($vms, ["vm-42"]);
    testing.assertEqual($seen[10].path, "/api/cis/tagging/tag/urn:t:2");
    testing.assertEqual($seen[11].path, "/api/cis/tagging/category/urn:c:2");
    testing.assertThrows("badCardinality", ERROR_KIND);
}

func testGuestNetworking() {
    def f as Fake init fake([
        ok(
            '[{"mac_address":"00:50:56:aa:bb:cc","nic":"4000","ip":{"ip_addresses":[' +
                '{"ip_address":"10.0.0.8","prefix_length":24,"origin":"DHCP",' +
                '"state":"PREFERRED"},' +
                '{"ip_address":"fe80::250:56ff:feaa:bbcc","prefix_length":64,' +
                '"state":"UNKNOWN"}]}},' +
                '{"mac_address":"02:42:ac:11:00:01",' +
                '"ip":{"ip_addresses":[{"ip_address":"172.17.0.1","prefix_length":16}]}}]'),
        ok('[]')
    ]);
    def c as Client init sessionClient($f);
    def is as list of GuestInterface init guestInterfaces($c, "vm-42");
    def none as list of string init guestAddresses($c, "vm-43");
    def seen as list of Seen init finish($f);
    testing.assertEqual($is[0].addresses, ["10.0.0.8/24", "fe80::250:56ff:feaa:bbcc/64"]);
    testing.assertEqual($is[1].nic, "");
    testing.assertEqual($seen[0].path, "/api/vcenter/vm/vm-42/guest/networking/interfaces");
    testing.assertEqual($none, []);
}

func testGuestAddresses() {
    def f as Fake init fake([
        ok(
            '[{"mac_address":"m","nic":"4000",' +
                '"ip":{"ip_addresses":[{"ip_address":"10.0.0.8","prefix_length":24},' +
                '{"ip_address":"FE80::1","prefix_length":64},{"ip_address":"2001:db8::8",' +
                '"prefix_length":64}]}}]')
    ]);
    def ips as list of string init guestAddresses(sessionClient($f), "vm-42");
    finish($f);
    testing.assertEqual($ips, ["10.0.0.8", "2001:db8::8"]);
}

func testGuestProcesses() {
    def f as Fake init fake([
        ok("4242"),
        ok('{"name":"sh","path":"/bin/sh","started":"2026-11-03T10:00:00Z"}'),
        ok('{"name":"sh","started":"2026-11-03T10:00:00Z"}'),
        ok('{"name":"sh","started":"2026-11-03T10:00:00Z",' +
            '"finished":"2026-11-03T10:00:02Z","exit_code":3}'),
        ok('"oops"')
    ]);
    def c as Client init withPollInterval(sessionClient($f), 1);
    def pid as int init runInGuest($c, "vm-42", rootLogin(), "/bin/sh", "-c \"uptime > /tmp/up\"");
    def now as GuestProcess init guestProcess($c, "vm-42", rootLogin(), $pid);
    def done as GuestProcess init waitGuestProcess($c, "vm-42", rootLogin(), $pid, 0);
    try {
        runInGuest($c, "vm-42", rootLogin(), "/bin/true", "");
        missed("a reply without a pid passed");
    } catch (e) {
        testing.assertEqual($e.message, "vmware: runInGuest returned no process id");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($pid, 4242);
    testing.assertEqual($seen[0].path, "/api/vcenter/vm/vm-42/guest/processes");
    testing.assertEqual($seen[0].query, "action=create");
    def body as json.Value init json.decode($seen[0].body);
    testing.assertEqual(json.asString($body, "/credentials/type"), "USERNAME_PASSWORD");
    testing.assertEqual(json.asString($body, "/credentials/user_name"), "root");
    testing.assertEqual(json.asBool($body, "/credentials/interactive_session"), false);
    testing.assertEqual(json.asString($body, "/spec/arguments"), "-c \"uptime > /tmp/up\"");
    testing.assertEqual($seen[1].path, "/api/vcenter/vm/vm-42/guest/processes/4242");
    testing.assertEqual($seen[1].query, "action=get");
    testing.assertEqual($now, GuestProcess{pid: 4242, finished: false, exitCode: 0});
    testing.assertEqual($done, GuestProcess{pid: 4242, finished: true, exitCode: 3});
}

func testReviewFixes() {
    testing.assertEqual(baseUrl("fd00::5"), "https://[fd00::5]");
    testing.assertEqual(baseUrl("[fd00::5]:8443"), "https://[fd00::5]:8443");
    def bare as Client;
    testing.assertEqual(pollDelay($bare), 1000);
    testing.assertEqual(isLocalAddress("169.254.1.1"), true);
    testing.assertEqual(getMany(client("vc"), []), []);
}

func testABatchStopsAtTheFirstRefusal() {
    def f as Fake init fake([
        ok('["urn:t:1","urn:t:2","urn:t:3"]'),
        ok('{"name":"a","category_id":"c"}'),
        Reply{status: 401, body: '{"error_type":"UNAUTHENTICATED","messages":[]}'}
    ]);
    try {
        tags(sessionClient($f));
        missed("a refused batch passed");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "vmware: GET /api/cis/tagging/tag/urn%3At%3A2: HTTP 401 UNAUTHENTICATED");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[2].session, "b00db39f948d13ea1e59b814e6e1ed4e");
}

func testWaitingRetriesOutagesButNotRefusals() {
    def f as Fake init fake([
        Reply{status: 503, body: ""},
        ok('{"status":"SUCCEEDED","result":"vm-9"}'),
        Reply{status: 502, body: ""},
        ok('{"name":"sh","finished":"2026-11-03T10:00:02Z","exit_code":0}'),
        Reply{status: 401, body: '{"error_type":"UNAUTHENTICATED","messages":[]}'}
    ]);
    def c as Client init withPollInterval(sessionClient($f), 1);
    def t as Task init waitTask($c, "task-1", 0);
    def p as GuestProcess init waitGuestProcess($c, "vm-42", rootLogin(), 7, 0);
    try {
        waitTask($c, "task-1", 0);
        missed("a 401 was retried");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "HTTP 401 UNAUTHENTICATED"));
    }
    finish($f);
    testing.assertEqual($t.result, "vm-9");
    testing.assertEqual($p.finished, true);
}

func testWaitingGivesUpAfterTooManyFailures() {
    def replies as list of Reply init [];
    for (def i in lists.range(0, MAX_POLL_FAILURES)) {
        $replies[] = Reply{status: 500, body: ""};
    }
    def f as Fake init fake($replies);
    try {
        waitTask(withPollInterval(sessionClient($f), 1), "task-1", 0);
        missed("waitTask retried for ever");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "HTTP 500"));
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($seen), MAX_POLL_FAILURES);
}

func testEnsureSession() {
    def f as Fake init fake([
        Reply{status: 201, body: '"s1"'},
        ok('{"user":"VSPHERE.LOCAL\\\\ada"}'),
        Reply{status: 401, body: '{"error_type":"UNAUTHENTICATED","messages":[]}'},
        Reply{status: 201, body: '"s2"'},
        Reply{status: 503, body: ""}
    ]);
    def c as Client init ensureSession(client($f.url), "ada", "pw");
    testing.assertEqual($c.session, "s1");
    testing.assertEqual(ensureSession($c, "ada", "pw").session, "s1");
    $c = ensureSession($c, "ada", "pw");
    testing.assertEqual($c.session, "s2");
    try {
        ensureSession($c, "ada", "pw");
        missed("a 503 led to a new login");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "HTTP 503"));
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[1].method, "GET");
    testing.assertEqual($seen[1].path, "/api/session");
    testing.assertEqual($seen[2].session, "s1");
    testing.assertEqual($seen[3].auth, http.basic("ada", "pw"));
}

func testDescribeHidesTheSession() {
    testing.assertEqual(describe(sessionClientFor("https://vc")), "https://vc (session)");
    testing.assertEqual(
        describe(withInsecure(client("vc"))),
        "https://vc (no session, certificate not checked)");
}

/**
 * A client with a session for a URL.
 *
 * @param url {string} the URL
 * @return {Client} the client
 */
func sessionClientFor(url as string) {
    return withSession(client($url), "b00db39f948d13ea1e59b814e6e1ed4e");
}
