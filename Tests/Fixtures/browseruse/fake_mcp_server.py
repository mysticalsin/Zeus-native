#!/usr/bin/env python3
"""A stand-in for `uvx browser-use --mcp` for the MCPStdioClient tests: newline-delimited JSON-RPC
over stdio, answering from the responses recorded in example-com.json. Extra tools for the tests:
  slow   never answers (timeout test)
  crash  exits at once, after a line on stderr
  ping   asks the client to ping first and answers once the client has replied
"""
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
recorded = json.load(open(os.path.join(here, "example-com.json")))
responses = {e["msg"]["id"]: e["msg"] for e in recorded if e["dir"] == "<-"}

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

sys.stderr.write("fake browser-use: started\n")
sys.stderr.flush()
pending_ping = None
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    method = msg.get("method")
    if method is None:
        if pending_ping is not None and msg.get("id") == "ping-1":
            send({"jsonrpc": "2.0", "id": pending_ping, "result": {"content": [{"type": "text", "text": "pong-ok"}], "isError": False}})
            pending_ping = None
        continue
    if "id" not in msg:
        continue  # notification
    mid = msg["id"]
    if method == "initialize":
        send({"jsonrpc": "2.0", "method": "notifications/message", "params": {"level": "info", "data": "hello"}})
        send({**responses[1], "id": mid})
    elif method == "tools/list":
        send({**responses[2], "id": mid})
    elif method == "tools/call":
        name = msg["params"]["name"]
        args = msg["params"].get("arguments", {})
        if name == "slow":
            continue
        if name == "crash":
            sys.stderr.write("fake browser-use: Chromium failed to start\n")
            sys.stderr.flush()
            sys.exit(3)
        if name == "ping":
            pending_ping = mid
            send({"jsonrpc": "2.0", "id": "ping-1", "method": "ping"})
            continue
        if name == "browser_navigate":
            text = "Navigated to: " + args.get("url", "")
        elif name == "browser_get_state":
            text = responses[4]["result"]["content"][0]["text"]
        else:
            send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "Error: Unknown tool: " + name}], "isError": True}})
            continue
        send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}], "isError": False}})
    else:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "Method not found"}})
