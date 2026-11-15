#!/usr/bin/env python3
"""End-to-end tests: runs a debug build of Raven Island beside the real one (its own folder and socket)
and drives it through the helper the way Claude Code would.

Debug builds honour RAVENISLAND_HOME and include the `resolve` command that stands in for a click;
release builds have neither. Run with:  python3 scripts/e2e.py
"""
import json, os, signal, socket, struct, subprocess, sys, threading, time, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
subprocess.run(["swift", "build"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
BIN = subprocess.run(["swift", "build", "--show-bin-path"], capture_output=True, text=True, check=True).stdout.strip()
BRIDGE, APP = os.path.join(BIN, "ravenisland-bridge"), os.path.join(BIN, "RavenIslandApp")
# Short path: Unix socket paths are limited to about 100 characters.
HOME_DIR = os.path.expanduser(f"~/.ravenisland-e2e-{os.getpid()}")
ENV = dict(os.environ, RAVENISLAND_HOME=HOME_DIR)
SOCK = os.path.join(HOME_DIR, "ravenisland.sock")

results = []
def check(name, ok, detail=""):
    results.append(ok)
    print(("  ok    " if ok else "  FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))

def bridge(*args, stdin=None, timeout=20):
    return subprocess.run([BRIDGE, *args], input=stdin, capture_output=True, text=True, env=ENV, timeout=timeout)

def hook(payload, **kw):
    return bridge("hook", "claude", stdin=json.dumps(payload), **kw)

def hook_bg(payload):
    p = subprocess.Popen([BRIDGE, "hook", "claude"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=ENV)
    p.stdin.write(json.dumps(payload)); p.stdin.close()
    p.stdin = None   # so communicate() later only reads
    return p

def pending():
    out = bridge("pending").stdout
    return json.loads(out) if out.strip() else []

def wait_for(cond, seconds=3.0):
    end = time.time() + seconds
    while time.time() < end:
        if cond(): return True
        time.sleep(0.05)
    return cond()

def raw(envelope, hold=False):
    # A flood can briefly fill the listen queue; a real helper treats that as "app absent" and passes through.
    for attempt in range(50):
        s = socket.socket(socket.AF_UNIX)
        try:
            s.connect(SOCK); break
        except ConnectionRefusedError:
            s.close(); time.sleep(0.02)
    else:
        raise ConnectionRefusedError("listen queue stayed full")
    body = json.dumps(envelope).encode(); s.sendall(struct.pack(">I", len(body)) + body)
    if hold: return s
    s.close()

def perm(session="s1", command="npm run migrate"):
    return {"session_id": session, "hook_event_name": "PermissionRequest", "cwd": "/tmp/demo",
            "tool_name": "Bash", "tool_input": {"command": command}, "permission_suggestions": []}

def envelope(event, payload, blocking, v=1, agent="claude"):
    return {"v": v, "agent": agent, "event": event, "blocking": blocking, "payload": payload, "context": {"ancestors": []}}

app = None
def start_app():
    global app
    app = subprocess.Popen([APP, "--test-mode"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not wait_for(lambda: os.path.exists(SOCK) and bridge("pending").returncode == 0, 8):
        print("app did not start"); sys.exit(1)

def cleanup():
    if app and app.poll() is None: app.terminate()
    shutil.rmtree(HOME_DIR, ignore_errors=True)

try:
    os.makedirs(HOME_DIR, mode=0o700, exist_ok=True)

    print("app not running")
    r = hook(perm())
    check("request passes through silently", r.returncode == 0 and r.stdout == "")

    start_app()
    print("answering from the panel")
    p = hook_bg(perm()); wait_for(lambda: len(pending()) == 1)
    check("request is queued", len(pending()) == 1)
    bridge("resolve", "allow"); out = p.communicate(timeout=5)[0]
    check("allow reaches the agent", json.loads(out)["hookSpecificOutput"]["decision"] == {"behavior": "allow"}, out)
    check("queue is empty afterwards", pending() == [])

    p = hook_bg(perm()); wait_for(lambda: len(pending()) == 1)
    bridge("resolve", "deny", "--message", "use staging"); out = p.communicate(timeout=5)[0]
    d = json.loads(out)["hookSpecificOutput"]["decision"]
    check("deny carries the note", d["behavior"] == "deny" and d["message"] == "use staging", out)

    print("settled somewhere else")
    p = hook_bg(perm()); wait_for(lambda: len(pending()) == 1); p.kill(); p.wait()
    check("card goes when the agent cancels", wait_for(lambda: pending() == []))
    p = hook_bg(perm()); wait_for(lambda: len(pending()) == 1)
    hook({"session_id": "s1", "hook_event_name": "PostToolUse", "cwd": "/tmp/demo", "tool_name": "Bash", "tool_input": {"command": "npm run migrate"}})
    out = p.communicate(timeout=5)[0]
    check("answered in the terminal: nothing sent, card gone", out == "" and pending() == [], out)

    print("several at once")
    a = hook_bg(perm("sA")); wait_for(lambda: len(pending()) == 1)
    q = hook_bg({"session_id": "sB", "hook_event_name": "PreToolUse", "cwd": "/tmp/demo", "tool_name": "AskUserQuestion",
                 "tool_input": {"questions": [{"question": "Red or Blue?", "options": [{"label": "Red"}, {"label": "Blue"}], "multiSelect": False}]}})
    wait_for(lambda: len(pending()) == 2)
    check("queued in arrival order", [x["kind"] for x in pending()] == ["permission", "question"])
    bridge("resolve", "allow"); bridge("resolve", "terminal")
    check("each answer goes to its own request", '"allow"' in a.communicate(timeout=5)[0] and q.communicate(timeout=5)[0] == "")

    print("decisions that overlap")
    first = hook_bg(perm("queue-a", "echo first"))
    wait_for(lambda: len(pending()) == 1)
    time.sleep(2)
    second = hook_bg(perm("queue-b", "echo second"))
    wait_for(lambda: len(pending()) == 2)
    time.sleep(5)   # well past the helper's 3 s silence limit: only heartbeats keep both alive
    check("both decisions are still waiting after 7 seconds", first.poll() is None and second.poll() is None
          and [x["session"] for x in pending()] == ["queue-a", "queue-b"])
    bridge("resolve", "allow")
    out = first.communicate(timeout=5)[0]
    check("answering the first leaves the second at the front", '"allow"' in out
          and [x["session"] for x in pending()] == ["queue-b"])
    bridge("resolve", "deny")
    check("then the second is answered", '"deny"' in second.communicate(timeout=5)[0] and pending() == [])
    for sid in ("queue-a", "queue-b"):
        hook({"session_id": sid, "hook_event_name": "SessionEnd"})

    print("what the command line reveals")
    hook({"session_id": "sP", "hook_event_name": "UserPromptSubmit", "cwd": "/Users/someone/secret-project", "prompt": "the secret prompt"})
    listing = bridge("sessions").stdout + bridge("pending").stdout
    check("no prompts or paths in sessions/pending", "secret" not in listing and "sP" in listing, listing[:200])

    print("hostile or broken input")
    held = [raw(envelope("StatusLine", {"session_id": "x"}, True), hold=True) for _ in range(300)]
    time.sleep(0.5)
    r = hook({"session_id": "s1", "hook_event_name": "Stop", "cwd": "/tmp/demo"})
    check("300 unanswerable connections don't stop the listener", bridge("pending").returncode == 0)
    for s in held: s.close()
    s = raw(envelope("PermissionRequest", perm(), True, v=99), hold=True); s.settimeout(3)
    try:
        n = struct.unpack(">I", s.recv(4))[0]; reply = json.loads(s.recv(n))
    except Exception as e: reply = {"error": str(e)}
    s.close()
    check("unknown protocol version is passed through", reply.get("passthrough") is True and pending() == [], str(reply))
    held = [raw(envelope("PermissionRequest", perm(f"flood{i}"), True), hold=True) for i in range(55)]
    wait_for(lambda: len(pending()) >= 40, 4); time.sleep(0.3)
    check("waiting requests are capped at 40", len(pending()) == 40, str(len(pending())))
    for s in held: s.close()
    check("queue drains when the connections close", wait_for(lambda: pending() == [], 5))
    r = bridge("resolve", "allow")
    check("resolve with nothing waiting does nothing", '"resolved" : false' in r.stdout or '"resolved":false' in r.stdout.replace(" ", ""), r.stdout)

    print("app frozen")
    os.kill(app.pid, signal.SIGSTOP)
    t = time.time(); r = hook(perm("frozen"), timeout=15); took = time.time() - t
    os.kill(app.pid, signal.SIGCONT)
    check("request falls back within 3 seconds", r.returncode == 0 and r.stdout == "" and took < 3.0, f"{took:.1f}s")
    check("no stale card after the app wakes", wait_for(lambda: pending() == [], 4))

    print("app hangs after the card is up")
    p = hook_bg(perm("hang")); wait_for(lambda: len(pending()) == 1); time.sleep(1.2)
    os.kill(app.pid, signal.SIGSTOP)
    t = time.time(); p.wait(timeout=15); took = time.time() - t
    os.kill(app.pid, signal.SIGCONT)
    check("request falls back within 5 seconds of the app freezing", p.returncode == 0 and took < 5.0, f"{took:.1f}s")
    check("its card is gone once the app wakes", wait_for(lambda: pending() == [], 4))

    print("forged usage report with an absurd reset time")
    raw(envelope("StatusLine", {"rate_limits": {"five_hour": {"used_percentage": 50, "resets_at": 1e30}}}, False))
    time.sleep(0.3)
    hook({"session_id": "usage", "hook_event_name": "Notification", "cwd": "/tmp/demo", "notification_type": "agent_needs_input"})
    time.sleep(1.5)
    check("app survives with the panel open", app.poll() is None)
    hook({"session_id": "usage", "hook_event_name": "SessionEnd"})

    print("large tool results")
    big = {"session_id": "big", "hook_event_name": "PostToolUse", "cwd": "/tmp/demo", "tool_name": "Grep",
           "tool_input": {"pattern": "x"}, "tool_response": [{"file": f"/a/{i}.ts", "line": i, "text": "match"} for i in range(20000)]}
    times = []
    for _ in range(5):
        t = time.time(); hook(big); times.append(time.time() - t)
    times.sort()
    check("20,000 search matches cost under 100 ms per tool call", times[2] < 0.1, f"median {times[2] * 1000:.0f} ms")
    hook({"session_id": "big", "hook_event_name": "SessionEnd"})

    print("slow senders")
    trickle = []
    for _ in range(40):
        s = socket.socket(socket.AF_UNIX); s.connect(SOCK); s.sendall(b"\x00"); trickle.append(s)
    t = time.time()
    hook({"session_id": "after-trickle", "hook_event_name": "UserPromptSubmit", "cwd": "/tmp/demo", "prompt": "x"})
    seen = wait_for(lambda: "after-trickle" in bridge("sessions").stdout, 5)
    check("real events still get through while 40 connections trickle", seen, f"{time.time() - t:.1f}s")
    for s in trickle:
        try: s.sendall(b"\x00")
        except OSError: pass
    time.sleep(2.5)
    dropped = 0
    for s in trickle:
        try:
            s.settimeout(0.5)
            if s.recv(1) == b"": dropped += 1
        except (OSError, socket.timeout): dropped += 1
        s.close()
    check("trickling connections are dropped after their deadline", dropped == 40, f"{dropped}/40")
    hook({"session_id": "after-trickle", "hook_event_name": "SessionEnd"})

    print("another process takes over the socket")
    app.terminate(); app.wait(timeout=5)
    if os.path.exists(SOCK): os.unlink(SOCK)
    fake = socket.socket(socket.AF_UNIX); fake.bind(SOCK); fake.listen(4)
    got = []
    def impostor():
        try:
            c, _ = fake.accept(); c.settimeout(2)
            got.append(c.recv(65536))
            allow = json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}})
            for frame in ({"v": 1, "ack": True}, {"v": 1, "stdout": allow}):
                b = json.dumps(frame).encode(); c.sendall(struct.pack(">I", len(b)) + b)
            c.close()
        except OSError:
            pass
    threading.Thread(target=impostor, daemon=True).start()
    r = hook(perm("impostor"))
    check("helper ignores an impostor and prints nothing", r.stdout == "", r.stdout[:80])
    check("helper sends the impostor nothing", got in ([], [b""]), str(got)[:80])
    fake.close(); os.unlink(SOCK)
    start_app()

    print("app quits")
    p = hook_bg(perm()); wait_for(lambda: len(pending()) == 1)
    app.terminate(); app.wait(timeout=5)
    out = p.communicate(timeout=5)[0]
    check("waiting request falls back when the app quits", out == "" and p.returncode == 0, out)

    release = os.path.join(ROOT, "build/Raven Island.app/Contents/Helpers/ravenisland-bridge")
    if os.path.exists(release):
        print("release build")
        r = subprocess.run([release, "resolve", "allow"], capture_output=True, text=True)
        check("release helper has no resolve command", r.returncode == 2 and "usage" in r.stdout, r.stdout[:80])
        # A release helper must ignore RAVENISLAND_HOME: point it at a folder whose remembered status line
        # prints a marker, and make sure that command is not the one that runs.
        os.makedirs(HOME_DIR, mode=0o700, exist_ok=True)
        with open(os.path.join(HOME_DIR, "previous-statusline.json"), "w") as f:
            json.dump({"type": "command", "command": "echo E2E-MARKER"}, f)
        debug = subprocess.run([BRIDGE, "statusline"], input="{}", capture_output=True, text=True, env=ENV)
        rel = subprocess.run([release, "statusline"], input="{}", capture_output=True, text=True, env=ENV)
        check("release helper ignores RAVENISLAND_HOME", "E2E-MARKER" in debug.stdout and "E2E-MARKER" not in rel.stdout, rel.stdout[:80])
finally:
    cleanup()

failed = results.count(False)
print(f"\n{len(results) - failed} passed, {failed} failed")
sys.exit(1 if failed else 0)
