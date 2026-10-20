ObjC.import("AppKit");
ObjC.import("Foundation");
ObjC.bindFunction("kill", ["int", ["int", "int"]]);

var BUNDLE_ID = "com.toyamarinyon.ayre";
var PROTOCOL_VERSION = 1;
var CAPABILITY = "put";
var MAX_PROBE_OUTPUT = 65536;
var PROBE_TIMEOUT_MS = 3000;
var CLI_TIMEOUT_MS = 10000;

function text(value) {
    return ObjC.unwrap(value);
}

function error(message) {
    throw new Error("Ayre: " + message);
}

function currentArguments() {
    var values = $.NSProcessInfo.processInfo.arguments;
    var result = [];
    for (var i = 4; i < text(values.count); i++) {
        result.push(text(values.objectAtIndex(i)));
    }
    return result;
}

function regularFile(path) {
    var attributes = $.NSFileManager.defaultManager.attributesOfItemAtPathError(path, Ref());
    if (!attributes) return false;
    return text(attributes.objectForKey($.NSFileType)) === text($.NSFileTypeRegular);
}

function executable(path) {
    return !!$.NSFileManager.defaultManager.isExecutableFileAtPath(path);
}

function exists(path) {
    return !!$.NSFileManager.defaultManager.fileExistsAtPath(path);
}

function bundleIdentifier(appPath) {
    var infoPath = appPath + "/Contents/Info.plist";
    var info = $.NSDictionary.dictionaryWithContentsOfFile(infoPath);
    if (!info) return null;
    var value = info.objectForKey("CFBundleIdentifier");
    return value ? text(value) : null;
}

function launchServicesApplications() {
    var urls = $.NSWorkspace.sharedWorkspace.URLsForApplicationsWithBundleIdentifier(BUNDLE_ID);
    var result = [];
    for (var i = 0; i < text(urls.count); i++) {
        result.push(text(urls.objectAtIndex(i).path));
    }
    return result;
}

function resolve(cliCandidates, applications, lookup) {
    var seenCli = {};
    for (var i = 0; i < cliCandidates.length; i++) {
        var candidate = cliCandidates[i];
        if (seenCli[candidate] || !lookup.executable(candidate)) continue;
        seenCli[candidate] = true;
        if (lookup.compatible(candidate)) return candidate;
    }

    var valid = [];
    var stale = [];
    var seenApps = {};
    for (var j = 0; j < applications.length; j++) {
        var appPath = applications[j];
        var canonical = lookup.canonical(appPath);
        if (seenApps[canonical]) continue;
        seenApps[canonical] = true;
        if (!lookup.exists(canonical) || lookup.bundleIdentifier(canonical) !== BUNDLE_ID) {
            stale.push(appPath);
            continue;
        }
        var appCLI = canonical + "/Contents/MacOS/ayre";
        if (!lookup.executable(appCLI)) {
            stale.push(appPath);
            continue;
        }
        if (lookup.compatible(appCLI)) valid.push(appCLI);
    }

    if (valid.length === 1) return valid[0];
    if (valid.length > 1) {
        valid.sort();
        error("Multiple compatible Ayre applications are registered: " + valid.join(", ") +
            ". Remove unused Ayre app copies and reopen the desired app, or put its compatible ayre CLI on PATH to select it.");
    }
    if (stale.length) {
        stale.sort();
        error("Launch Services returned Ayre application entries that are missing or stale: " +
            stale.join(", ") + ". Refresh the app registration or put a compatible ayre CLI on PATH.");
    }
    error("No compatible Ayre CLI was found on PATH or in Launch Services. Install Ayre or make a compatible ayre executable available on PATH.");
}

function pathCandidates() {
    var environment = $.NSProcessInfo.processInfo.environment;
    var pathValue = environment.objectForKey("PATH");
    var path = pathValue ? text(pathValue) : "";
    return path.split(":").filter(function (part) {
        return part.length > 0;
    }).map(function (part) {
        return part.replace(/\/+$/, "") + "/ayre";
    });
}

function waitForTask(task, timeoutMs) {
    var deadline = Date.now() + timeoutMs;
    while (task.isRunning && Date.now() < deadline) {
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
    }
    if (!task.isRunning) return true;

    task.terminate;
    var graceDeadline = Date.now() + 200;
    while (task.isRunning && Date.now() < graceDeadline) {
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.02));
    }
    if (task.isRunning) $.kill(task.processIdentifier, 9);
    return false;
}

function writeStdout(value) {
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(
        $.NSString.stringWithString(value + "\n").dataUsingEncoding($.NSUTF8StringEncoding)
    );
}

function capabilitiesFor(path) {
    var outputPath = text($.NSTemporaryDirectory()).replace(/\/+$/, "") +
        "/ayre-probe-" + text($.NSUUID.UUID.UUIDString);
    var fileManager = $.NSFileManager.defaultManager;
    if (!fileManager.createFileAtPathContentsAttributes(outputPath, $.NSData.data, $.nil)) return null;
    var outputHandle = $.NSFileHandle.fileHandleForWritingAtPath(outputPath);
    if (!outputHandle) {
        fileManager.removeItemAtPathError(outputPath, Ref());
        return null;
    }

    var task = $.NSTask.alloc.init;
    task.launchPath = path;
    task.arguments = ObjC.wrap(["capabilities", "--json"]);
    task.standardOutput = outputHandle;
    task.standardError = outputHandle;
    var launchError = Ref();
    if (!task.launchAndReturnError(launchError)) {
        outputHandle.closeFile;
        fileManager.removeItemAtPathError(outputPath, Ref());
        return null;
    }

    var completed = waitForTask(task, PROBE_TIMEOUT_MS);
    outputHandle.closeFile;
    var attributes = fileManager.attributesOfItemAtPathError(outputPath, Ref());
    var outputSize = attributes ? Number(text(attributes.objectForKey($.NSFileSize))) : MAX_PROBE_OUTPUT + 1;
    var data = completed && outputSize <= MAX_PROBE_OUTPUT
        ? $.NSData.dataWithContentsOfFile(outputPath) : null;
    fileManager.removeItemAtPathError(outputPath, Ref());
    if (!completed || !data || Number(text(data.length)) > MAX_PROBE_OUTPUT ||
        Number(text(task.terminationStatus)) !== 0) return null;
    try {
        var jsonString = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
        var json = JSON.parse(text(jsonString));
        if (json.protocolVersion === PROTOCOL_VERSION &&
            Array.isArray(json.capabilities) && json.capabilities.indexOf(CAPABILITY) !== -1 &&
            typeof json.version === "string" && /^\d+\.\d+\.\d+$/.test(json.version)) {
            return json;
        }
    } catch (e) {
        return null;
    }
    return null;
}

function probeCompatible(path) {
    return capabilitiesFor(path) !== null;
}

function resolveAyre(cliCandidates, applications, compatible) {
    return resolve(cliCandidates, applications, {
        canonical: function (path) {
            return text($.NSURL.fileURLWithPath(path).URLByStandardizingPath.URLByResolvingSymlinksInPath.path);
        },
        exists: exists,
        executable: executable,
        bundleIdentifier: bundleIdentifier,
        compatible: compatible
    });
}

function makeDirectory(path) {
    var fileManager = $.NSFileManager.defaultManager;
    var errorOut = Ref();
    var result = fileManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(
        path, true, $.nil, errorOut
    );
    if (!result) {
        var detail = errorOut[0] ? text(errorOut[0].localizedDescription) : "unknown file system error";
        error("Could not create directory " + path + ": " + detail);
    }
}

function tempDirectory() {
    var base = text($.NSTemporaryDirectory()).replace(/\/+$/, "");
    for (var i = 0; i < 8; i++) {
        var path = base + "/ayre-prompt-" + text($.NSUUID.UUID.UUIDString);
        if (exists(path)) continue;
        try {
            makeDirectory(path);
            return path;
        } catch (e) {
            continue;
        }
    }
    error("Could not create a unique temporary directory for the prompt.");
}

function validateTempDirectory(path) {
    var base = text($.NSURL.fileURLWithPath(text($.NSTemporaryDirectory()))
        .URLByStandardizingPath.URLByResolvingSymlinksInPath.path).replace(/\/+$/, "");
    var directory = text($.NSURL.fileURLWithPath(path).URLByStandardizingPath
        .URLByResolvingSymlinksInPath.path);
    var parent = directory.substring(0, directory.lastIndexOf("/"));
    var leaf = directory.substring(directory.lastIndexOf("/") + 1);
    if (parent !== base || leaf.indexOf("ayre-prompt-") !== 0 ||
        !exists(directory) || regularFile(directory)) {
        error("The temporary directory was not created by this Ayre helper.");
    }
    return directory;
}

function readData(path) {
    var data = $.NSData.dataWithContentsOfFile(path);
    if (!data) error("Could not read " + path + ".");
    return data;
}

function readJSON(path) {
    var data = readData(path);
    var string = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!string) error("request.json must be UTF-8 JSON.");
    try {
        return JSON.parse(text(string));
    } catch (e) {
        error("request.json must be valid JSON.");
    }
}

function checkRegularNonSymlink(path) {
    var attributes = $.NSFileManager.defaultManager.attributesOfItemAtPathError(path, Ref());
    if (!attributes ||
        text(attributes.objectForKey($.NSFileType)) !== text($.NSFileTypeRegular)) {
        error("Temporary directory must contain regular prompt.md and request.json files.");
    }
}

function runAyre(path, request, promptPath) {
    var args = ["put", request.slug, "--title", request.title];
    if (request.overwrite === true) args.push("--overwrite");

    var task = $.NSTask.alloc.init;
    task.launchPath = path;
    task.arguments = ObjC.wrap(args);
    task.standardInput = $.NSFileHandle.fileHandleForReadingAtPath(promptPath);
    task.standardOutput = $.NSFileHandle.fileHandleWithStandardOutput;
    task.standardError = $.NSFileHandle.fileHandleWithStandardError;
    var launchError = Ref();
    if (!task.launchAndReturnError(launchError)) {
        error("Could not run Ayre CLI at " + path + ".");
    }
    if (!waitForTask(task, CLI_TIMEOUT_MS)) {
        error("Ayre CLI did not finish within 10 seconds and was stopped.");
    }
    if (Number(text(task.terminationStatus)) !== 0) {
        error("Ayre CLI exited with status " + text(task.terminationStatus) + ".");
    }
}

function cleanupTempDirectory(path) {
    var manager = $.NSFileManager.defaultManager;
    manager.removeItemAtPathError(path + "/prompt.md", Ref());
    manager.removeItemAtPathError(path + "/request.json", Ref());
    manager.removeItemAtPathError(path, Ref());
}

function put(directory, injected) {
    directory = validateTempDirectory(directory);
    var promptPath = directory + "/prompt.md";
    var requestPath = directory + "/request.json";
    checkRegularNonSymlink(promptPath);
    checkRegularNonSymlink(requestPath);
    var promptData = readData(promptPath);
    if (text(promptData.length) > 1000000) error("Prompt exceeds Ayre's 1,000,000-byte limit.");
    var request = readJSON(requestPath);
    if (!request || typeof request.slug !== "string" || !request.slug ||
        typeof request.title !== "string" || !request.title ||
        (request.overwrite !== undefined && typeof request.overwrite !== "boolean")) {
        error("request.json must include non-empty slug and title strings and an optional boolean overwrite value.");
    }

    var candidates = injected ? injected.cliCandidates : pathCandidates();
    var apps = injected ? injected.applications : launchServicesApplications();
    var cli = resolveAyre(candidates, apps, injected ? injected.compatible : probeCompatible);
    runAyre(cli, request, promptPath);
    cleanupTempDirectory(directory);
}

function createTestDirectory(base, leaf) {
    var path = base + "/" + leaf;
    makeDirectory(path);
    return path;
}

function writeData(path, data) {
    if (!data.writeToFileAtomically(path, true)) error("Test setup could not write " + path + ".");
}

function stringData(value) {
    return $.NSString.stringWithString(value).dataUsingEncoding($.NSUTF8StringEncoding);
}

function sameBytes(a, b) {
    return !!a.isEqualToData(b);
}

function runSelfTests() {
    var base = text($.NSTemporaryDirectory()).replace(/\/+$/, "") +
        "/ayre plugin tests " + text($.NSUUID.UUID.UUIDString);
    makeDirectory(base);
    try {
        var pathCLI = base + "/PATH bin with spaces/ayre";
        var appOne = base + "/Ayre app with spaces.app";
        var appTwo = base + "/Second Ayre.app";
        makeDirectory(base + "/PATH bin with spaces");
        makeDirectory(appOne + "/Contents/MacOS");
        makeDirectory(appTwo + "/Contents/MacOS");

        var executablePaths = {};
        executablePaths[pathCLI] = true;
        executablePaths[appOne + "/Contents/MacOS/ayre"] = true;
        executablePaths[appTwo + "/Contents/MacOS/ayre"] = true;
        var bundleIDs = {};
        bundleIDs[appOne] = BUNDLE_ID;
        bundleIDs[appTwo] = BUNDLE_ID;
        var compatiblePaths = {};
        compatiblePaths[pathCLI] = true;
        compatiblePaths[appOne + "/Contents/MacOS/ayre"] = true;
        compatiblePaths[appTwo + "/Contents/MacOS/ayre"] = true;
        var lookup = {
            canonical: function (p) { return p; },
            exists: function (p) { return !!bundleIDs[p]; },
            executable: function (p) { return !!executablePaths[p]; },
            bundleIdentifier: function (p) { return bundleIDs[p] || null; },
            compatible: function (p) { return !!compatiblePaths[p]; }
        };
        var preferred = resolve([pathCLI], [appOne], lookup);
        if (preferred !== pathCLI) error("Self-test failed: compatible PATH CLI was not preferred.");

        var fallback = resolve([pathCLI], [base + "/stale Ayre.app", appOne], {
            canonical: lookup.canonical,
            exists: lookup.exists,
            executable: lookup.executable,
            bundleIdentifier: lookup.bundleIdentifier,
            compatible: function (p) { return p === appOne + "/Contents/MacOS/ayre"; }
        });
        if (fallback !== appOne + "/Contents/MacOS/ayre") error("Self-test failed: stale match was not skipped.");

        var duplicate = resolve([], [appOne, appOne], lookup);
        if (duplicate !== appOne + "/Contents/MacOS/ayre") error("Self-test failed: duplicate match was not deduplicated.");

        var ambiguous = false;
        try {
            resolve([], [appOne, appTwo], lookup);
        } catch (e) {
            ambiguous = String(e).indexOf("Multiple compatible Ayre applications") !== -1 &&
                String(e).indexOf("spaces") !== -1;
        }
        if (!ambiguous) error("Self-test failed: multiple compatible matches were not reported clearly.");

        var fakeBin = createTestDirectory(base, "fake CLI bin with spaces");
        var fakeCLI = fakeBin + "/ayre";
        var captured = base + "/captured stdin bytes";
        var capturedArgs = base + "/captured argv bytes";
        var shellQuote = function (s) { return "'" + s.replace(/'/g, "'\\''") + "'"; };
        var fakeScript = "#!/bin/sh\n" +
            "if [ \"$1\" = \"capabilities\" ]; then\n" +
            "  printf '%s\\n' '{\"protocolVersion\":1,\"version\":\"0.2.0\",\"capabilities\":[\"put\"]}'\n" +
            "  exit 0\n" +
            "fi\n" +
            "printf '%s\\n' \"$@\" > " + shellQuote(capturedArgs) + "\n" +
            "cat > " + shellQuote(captured) + "\n";
        writeData(fakeCLI, stringData(fakeScript));
        var chmod = $.NSTask.alloc.init;
        chmod.launchPath = "/bin/chmod";
        chmod.arguments = ObjC.wrap(["700", fakeCLI]);
        if (!chmod.launchAndReturnError(Ref())) error("Self-test setup could not chmod fake CLI.");
        chmod.waitUntilExit;

        var promptPath = base + "/prompt body.md";
        var requestPath = base + "/request.json";
        var promptBytes = stringData("# Café 🧭\r\n\r\n  x\t\r\n");
        writeData(promptPath, promptBytes);
        var hostileTitle = "Café $() ; ' \" title";
        writeData(requestPath, stringData(JSON.stringify({
            slug: "safe-slug",
            title: hostileTitle,
            overwrite: false
        })));
        var requestDir = text($.NSTemporaryDirectory()).replace(/\/+$/, "") +
            "/ayre-prompt-test-" + text($.NSUUID.UUID.UUIDString);
        makeDirectory(requestDir);
        var manager = $.NSFileManager.defaultManager;
        manager.moveItemAtPathToPathError(promptPath, requestDir + "/prompt.md", Ref());
        manager.moveItemAtPathToPathError(requestPath, requestDir + "/request.json", Ref());

        put(requestDir, {
            cliCandidates: [fakeCLI],
            applications: [],
            compatible: probeCompatible
        });

        var received = readData(captured);
        if (!sameBytes(received, promptBytes)) error("Self-test failed: stdin bytes changed, including CRLF or UTF-8.");
        if (!exists(capturedArgs)) error("Self-test failed: CLI argv was not captured.");
        var titleArgData = readData(capturedArgs);
        var expectedText = "put\nsafe-slug\n--title\n" + hostileTitle + "\n";
        var actualText = text($.NSString.alloc.initWithDataEncoding(titleArgData, $.NSUTF8StringEncoding));
        if (actualText.normalize("NFC") !== expectedText.normalize("NFC")) {
            error("Self-test failed: title was not passed as one literal argument.");
        }
        if (exists(requestDir)) error("Self-test failed: successful save left its temporary prompt directory behind.");
        console.log("Ayre plugin helper tests passed.");
    } finally {
        $.NSFileManager.defaultManager.removeItemAtPathError(base, Ref());
    }
}

function main() {
    var args = currentArguments();
    if (args.length === 1 && args[0] === "--self-test") {
        runSelfTests();
        return;
    }
    if (args.length === 1 && args[0] === "prepare") {
        var output = JSON.stringify({directory: tempDirectory()});
        writeStdout(output);
        return;
    }
    if (args.length === 2 && args[0] === "put") {
        put(args[1]);
        console.log("Saved Ayre prompt.");
        return;
    }
    if (args.length === 1 && args[0] === "resolve") {
        var path = resolveAyre(pathCandidates(), launchServicesApplications(), probeCompatible);
        var capabilities = capabilitiesFor(path);
        if (!capabilities) error("Selected Ayre CLI stopped responding during the final compatibility check.");
        writeStdout(JSON.stringify({
            path: path,
            version: capabilities.version,
            protocolVersion: capabilities.protocolVersion,
            capabilities: capabilities.capabilities
        }));
        return;
    }
    error("usage: ayre.js prepare | put <temporary-directory> | resolve | --self-test");
}

try {
    main();
} catch (e) {
    $.NSFileHandle.fileHandleWithStandardError.writeData(
        $.NSString.stringWithString(String(e) + "\n").dataUsingEncoding($.NSUTF8StringEncoding)
    );
    throw e;
}
