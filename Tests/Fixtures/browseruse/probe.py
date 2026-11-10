import json, subprocess, sys, os, time, select
sp = sys.argv[1]
env = dict(os.environ, ANONYMIZED_TELEMETRY="False", BROWSER_USE_CONFIG_PATH=sp+"/bu-probe/config.json", BROWSER_USE_CONFIG_DIR=sp+"/bu-probe/cfg")
p = subprocess.Popen(["uvx","browser-use","--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(sp+"/bu-probe/stderr.log","w"), env=env, text=True, bufsize=1)
log=[]
nid=[0]
def send(obj): p.stdin.write(json.dumps(obj)+"\n"); p.stdin.flush(); log.append({"dir":"->","msg":obj})
def recv(timeout=90):
    r,_,_=select.select([p.stdout],[],[],timeout)
    if not r: return None
    line=p.stdout.readline()
    m=json.loads(line); log.append({"dir":"<-","msg":m}); return m
def call(method, params=None, timeout=90):
    nid[0]+=1; i=nid[0]
    send({"jsonrpc":"2.0","id":i,"method":method,**({"params":params} if params is not None else {})})
    while True:
        m=recv(timeout)
        if m is None: return None
        if m.get("id")==i: return m
def tool(name,args,timeout=120): return call("tools/call",{"name":name,"arguments":args},timeout)
t0=time.time()
init=call("initialize",{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"zeus","version":"1"}})
print("init", json.dumps(init)[:600])
send({"jsonrpc":"2.0","method":"notifications/initialized"})
tl=call("tools/list",{})
print("tools", [t["name"] for t in tl["result"]["tools"]])
steps=[("browser_navigate",{"url":"https://example.com"}),("browser_get_state",{}),("browser_get_html",{}),("browser_list_tabs",{}),
 ("browser_scroll",{"direction":"down"}),("browser_click",{"index":1}),("browser_get_state",{}),("browser_go_back",{}),("browser_get_state",{}),
 ("browser_extract_content",{"query":"title"}),("browser_click",{"index":999}),("browser_nonexistent",{})]
for n,a in steps:
    r=tool(n,a); print(n,a,"->",json.dumps(r)[:700]); 
call("tools/call",{"name":"browser_close_all","arguments":{}})
json.dump(log,open(sp+"/bu-probe/transcript.json","w"),indent=1)
p.stdin.close()
try: p.wait(10)
except Exception: p.terminate()
print("exit",p.returncode, "secs", time.time()-t0)
