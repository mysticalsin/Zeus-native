import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { build } from "esbuild";

const compiled = await build({ entryPoints: ["src/sw.ts"], bundle: true, format: "iife", write: false });
const workerSource = compiled.outputFiles[0].text;

// Only synthetic native ports and tab metadata. No browser or account is contacted.
function session({ failFirstHello = false } = {}) {
  const ports = [], timers = [], queries = [], storage = [];
  let receivePopup;
  const chrome = {
    runtime: {
      connectNative() {
        const connection = {
          sent: [],
          onMessage: { addListener(listener) { connection.receive = listener; } },
          onDisconnect: { addListener(listener) { connection.disconnect = listener; } },
          postMessage(message) {
            if (failFirstHello && ports.length === 1 && message.id === "hello") {
              throw new Error("Synthetic disconnect before handshake");
            }
            connection.sent.push(message);
          },
        };
        ports.push(connection);
        return connection;
      },
      onMessage: { addListener(listener) { receivePopup = listener; } },
      onStartup: { addListener() {} },
      onInstalled: { addListener() {} },
    },
    storage: { local: { set: async value => { storage.push(value); } } },
    tabs: { query: () => new Promise(resolve => queries.push(resolve)) },
  };
  vm.runInNewContext(workerSource, {
    chrome, console: { warn() {}, info() {} },
    setTimeout(callback) { timers.push(callback); return timers.length; }, clearTimeout() {},
  });
  return { ports, timers, queries, storage, status() {
    let value;
    receivePopup({ type: "status" }, {}, result => { value = result; });
    return value;
  } };
}

test("a late reply cannot cross into a replacement native connection", async () => {
  const state = session(), original = state.ports[0];
  original.receive({ id: "reused-id", type: "tabs.list", params: {} });
  original.disconnect();
  state.timers.shift()();
  const replacement = state.ports[1];
  state.queries.shift()([{ id: 7, title: "Old synthetic tab", url: "https://example.invalid", active: true }]);
  await new Promise(setImmediate);
  assert.equal(original.sent.filter(message => message.id === "reused-id").length, 0);
  assert.equal(replacement.sent.filter(message => message.id === "reused-id").length, 0);

  replacement.receive({ id: "reused-id", type: "tabs.list", params: {} });
  state.queries.shift()([]);
  await new Promise(setImmediate);
  assert.equal(replacement.sent.filter(message => message.id === "reused-id").length, 1);
});

test("retired port events cannot dispatch work or disconnect its replacement", async () => {
  const state = session(), original = state.ports[0];
  original.disconnect();
  state.timers.shift()();
  const replacement = state.ports[1];
  original.receive({ id: "retired", type: "tabs.list", params: {} });
  assert.equal(state.queries.length, 0, "A retired port must not start a browser request");
  original.disconnect();
  assert.equal(state.timers.length, 0, "A stale disconnect must not schedule a reconnect");
  replacement.receive({ id: "current", type: "tabs.list", params: {} });
  state.queries.shift()([]);
  await new Promise(setImmediate);
  assert.equal(replacement.sent.filter(message => message.id === "current").length, 1);
});

test("a rejected handshake cannot be presented as connected", () => {
  const state = session();
  state.ports[0].receive({ id: "hello", ok: false, result: { version: "old" }, error: { message: "Synthetic refusal" } });
  assert.equal(state.status().connected, false);
  assert.match(state.status().detail, /Synthetic refusal/);
  assert.equal(state.storage.at(-1).bridgeConnected, false);
});

test("a retired handshake cannot replace current connection metadata", () => {
  const state = session(), original = state.ports[0];
  original.disconnect();
  state.timers.shift()();
  state.ports[1].receive({ id: "hello", ok: true, result: { version: "current" } });
  const writes = state.storage.length;
  original.receive({ id: "hello", ok: true, result: { version: "retired" } });
  assert.equal(state.storage.length, writes);
  assert.equal(state.status().connected, true);
  assert.equal(state.status().detail, "Bridge current is running.");
});

test("a port retired before its disconnect notification cannot reject the worker task", async () => {
  const state = session(), original = state.ports[0];
  original.receive({ id: "in-flight", type: "tabs.list", params: {} });
  original.postMessage = () => { throw new Error("Synthetic disconnected port"); };
  state.queries.shift()([]);
  await new Promise(setImmediate);
  assert.equal(state.ports.length, 1, "A failed reply must never replay the request on another connection");
  assert.equal(state.queries.length, 0);
});

test("a failed initial handshake send retires once and can reconnect", () => {
  const state = session({ failFirstHello: true });
  assert.equal(state.status().connected, false);
  assert.equal(state.timers.length, 1);
  state.ports[0].disconnect();
  assert.equal(state.timers.length, 1, "The delayed disconnect must not duplicate recovery");
  state.timers.shift()();
  assert.equal(state.ports.length, 2);
  assert.equal(state.ports[1].sent[0].id, "hello");
  state.ports[1].receive({ id: "hello", ok: true, result: { version: "recovered" } });
  assert.equal(state.status().connected, true);
});
