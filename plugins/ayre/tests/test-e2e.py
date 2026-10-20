#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "ayre.js"


def run(args, env):
    return subprocess.run(
        ["/usr/bin/osascript", "-l", "JavaScript", str(SCRIPT), *args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=15,
    )



def test_timeout_fallback(root):
    slow_bin = root / "slow PATH entry"
    good_bin = root / "fallback PATH entry"
    slow_bin.mkdir()
    good_bin.mkdir()
    slow_pid = root / "slow.pid"
    slow = slow_bin / "ayre"
    slow.write_text(
        "#!/usr/bin/python3\n"
        "import os, signal, sys, time\n"
        "if sys.argv[1:] == ['capabilities', '--json']:\n"
        " signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
        " open(os.environ['AYRE_SLOW_PID'], 'w').write(str(os.getpid()))\n"
        " while True: time.sleep(1)\n"
        " raise SystemExit(0)\n"
    )
    slow.chmod(0o700)
    good = good_bin / "ayre"
    good.write_text(
        "#!/usr/bin/python3\n"
        "import json, sys\n"
        "if sys.argv[1:] == ['capabilities', '--json']:\n"
        " print(json.dumps({'protocolVersion':1,'version':'0.2.0','capabilities':['put']}))\n"
        " raise SystemExit(0)\n"
    )
    good.chmod(0o700)
    env = os.environ.copy()
    env["PATH"] = str(slow_bin) + ":" + str(good_bin) + ":/usr/bin:/bin"
    env["AYRE_SLOW_PID"] = str(slow_pid)
    started = __import__("time").monotonic()
    result = run(["resolve"], env)
    elapsed = __import__("time").monotonic() - started
    selected = json.loads(result.stdout.decode())
    if selected["path"] != str(good):
        raise AssertionError(f"hung PATH candidate was not skipped: {selected!r}")
    if elapsed < 2.5 or elapsed >= 10:
        raise AssertionError(f"capability deadline was not bounded as expected: {elapsed:.2f}s")
    if not slow_pid.exists():
        raise AssertionError("slow fake CLI never started")
    pid = int(slow_pid.read_text())
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError(f"timed-out capability process {pid} is still running")
    print(f"Ayre capability timeout/fallback test passed ({elapsed:.2f}s).")


def main():
    with tempfile.TemporaryDirectory(prefix="ayre-plugin-e2e-") as root:
        root = Path(root)
        bindir = root / "fake PATH with spaces"
        bindir.mkdir()
        captured = root / "argv.bin"
        stdin_capture = root / "stdin.bin"
        cli = bindir / "ayre"
        cli.write_text(
            "#!/usr/bin/python3\n"
            "import json, os, sys\n"
            "if sys.argv[1:] == ['capabilities', '--json']:\n"
            " print(json.dumps({'protocolVersion':1,'version':'0.2.0','capabilities':['put']}))\n"
            " raise SystemExit(0)\n"
            "open(os.environ['AYRE_TEST_ARGV'], 'wb').write(b'\\0'.join(a.encode() for a in sys.argv[1:]))\n"
            "open(os.environ['AYRE_TEST_STDIN'], 'wb').write(sys.stdin.buffer.read())\n"
        )
        cli.chmod(0o700)
        env = os.environ.copy()
        env.update({
            "PATH": str(bindir) + ":/usr/bin:/bin",
            "AYRE_TEST_ARGV": str(captured),
            "AYRE_TEST_STDIN": str(stdin_capture),
        })

        prepared = run(["prepare"], env)
        request_dir = Path(json.loads(prepared.stdout.decode())["directory"])
        try:
            body = b"# not normalized \xc3\xa9\r\n\r\nline\twith $() ; 'quotes'\r\n"
            title = "Hostile\nTitle $() ; ' \""
            (request_dir / "prompt.md").write_bytes(body)
            (request_dir / "request.json").write_text(json.dumps({
                "slug": "test-prompt",
                "title": title,
                "overwrite": True,
            }))
            run(["put", str(request_dir)], env)
            args = captured.read_bytes().split(b"\0")
            expected = [b"put", b"test-prompt", b"--title", title.encode(), b"--overwrite"]
            if args != expected:
                raise AssertionError(f"CLI argv changed: {args!r}")
            if stdin_capture.read_bytes() != body:
                raise AssertionError("prompt stdin bytes changed")
            if request_dir.exists():
                raise AssertionError("successful put did not clean the temporary directory")
        finally:
            if request_dir.exists():
                import shutil
                shutil.rmtree(request_dir)
        print("Ayre wrapper end-to-end test passed.")
        test_timeout_fallback(root)


if __name__ == "__main__":
    main()
