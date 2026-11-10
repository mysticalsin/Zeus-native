import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { build } from "esbuild";

// Exercise the production service worker and its injected functions. Chrome is replaced only at
// the extension boundary; no real tabs, accounts, capture permissions or external service is used.
const compiled = await build({ entryPoints: ["src/sw.ts"], bundle: true, format: "iife", write: false });
const workerSource = compiled.outputFiles[0].text;

function browser() {
  let receive;
  let nextID = 0;
  const pending = new Map();
  const pages = new Map();
  const state = { active: 1, writes: [], removed: [], navigations: [], injections: [], beforeInject: undefined };
  for (const id of [1, 2]) {
    const url = `https://site${id}.example/form`;
    const page = { id, url, documentId: `document-${id}`, title: `Site ${id}` };
    page.context = vm.createContext({ location: { href: url }, effects: state.writes });
    vm.runInContext(`
      class HTMLElement {
        getBoundingClientRect() { return { width: 100, height: 30 }; }
        getAttribute(name) { return name === "aria-label" ? this.label : null; }
        scrollIntoView() {}
        focus() {}
        closest(selector) { return selector === "form" ? { requestSubmit() { effects.push("submit"); } } : null; }
        dispatchEvent() {}
      }
      class HTMLInputElement extends HTMLElement {
        constructor() { super(); this.label = "Search"; this.type = "text"; this.tagName = "INPUT"; this.isConnected = true; }
        set value(text) { effects.push("type:" + text); }
        get value() { return ""; }
      }
      class HTMLTextAreaElement extends HTMLElement {}
      class HTMLButtonElement extends HTMLElement {}
      const button = new HTMLButtonElement();
      button.label = "Save"; button.innerText = "Save"; button.isConnected = true;
      button.click = () => effects.push("click:Save");
      const field = new HTMLInputElement();
      const document = {
        title: "Fixture", body: { innerText: "Fixture text" }, activeElement: field,
        querySelectorAll(selector) { return selector.startsWith("input,") ? [field] : [button]; },
        querySelector() { return null; }
      };
      const CSS = { escape: value => value };
      const getSelection = () => "";
      const getComputedStyle = () => ({ visibility: "visible" });
      class Event { constructor(type) { this.type = type; } }
      globalThis.__zeusIndex = { state: "fixture-state", href: location.href, elements: [button, field], changes: 0 };
    `, page.context);
    pages.set(id, page);
  }
  const tab = id => {
    const page = pages.get(id);
    if (!page) throw new Error("No tab");
    return { id, url: page.url, title: page.title, active: state.active === id, status: "complete" };
  };
  const port = {
    onMessage: { addListener: listener => { receive = listener; } },
    onDisconnect: { addListener() {} },
    postMessage(message) {
      if (message.id === "hello") return;
      pending.get(message.id)?.(message);
      pending.delete(message.id);
    },
  };
  const chrome = {
    runtime: { connectNative: () => port, onMessage: { addListener() {} }, onStartup: { addListener() {} }, onInstalled: { addListener() {} } },
    storage: { local: { set: async () => {} } },
    tabs: {
      get: async id => tab(id),
      query: async query => query.active ? [tab(state.active)] : [...pages.keys()].map(tab),
      remove: async id => { state.removed.push(id); pages.delete(id); },
      goBack: async id => { state.navigations.push(["back", id]); },
      goForward: async id => { state.navigations.push(["forward", id]); },
      onUpdated: { addListener() {}, removeListener() {} },
    },
    scripting: {
      executeScript: async injection => {
        state.beforeInject?.(injection);
        state.injections.push(injection.target);
        const page = pages.get(injection.target.tabId);
        if (!page || (injection.target.documentIds && !injection.target.documentIds.includes(page.documentId))) {
          throw new Error("The approved document no longer exists");
        }
        page.context.location.href = page.url;
        page.context.args = injection.args ?? [];
        const result = await vm.runInContext(`(${injection.func.toString()})(...args)`, page.context);
        return [{ result, documentId: page.documentId, frameId: 0 }];
      },
    },
  };
  vm.runInNewContext(workerSource, { chrome, console: { warn() {}, info() {} }, setTimeout: () => 1, clearTimeout() {} });
  async function request(type, params = {}) {
    const id = String(++nextID);
    const result = new Promise(resolve => pending.set(id, resolve));
    receive({ id, type, params });
    return result;
  }
  async function target(params = {}) {
    const response = await request("page.target", params);
    assert.equal(response.ok, true);
    return response.result;
  }
  return { state, pages, request, target };
}

test("a mutation without a captured target fails closed", async () => {
  const b = browser();
  for (const type of ["page.click", "page.type", "page.click_index", "page.type_index", "page.select", "tab.back", "tab.forward", "tab.close"]) {
    const response = await b.request(type, { text: "Save", index: 1 });
    assert.equal(response.error.code, "stale_target", type);
  }
  assert.deepEqual(b.state.writes, []);
  assert.deepEqual(b.state.removed, []);
});

test("the approved tab and document receive a normal click", async () => {
  const b = browser();
  const pageTarget = await b.target();
  const response = await b.request("page.click", { text: "Save", pageTarget });
  assert.equal(response.ok, true);
  assert.deepEqual(b.state.writes, ["click:Save"]);
  assert.deepEqual(Array.from(b.state.injections.at(-1).documentIds), ["document-1"]);
});

for (const change of ["switch-tab", "navigate", "reload-same-url"]) {
  test(`${change} while consent is open cannot redirect a write`, async () => {
    const b = browser();
    const pageTarget = await b.target();
    if (change === "switch-tab") b.state.active = 2;
    if (change === "navigate") b.pages.get(1).url = "https://unapproved.example/";
    if (change === "reload-same-url") b.pages.get(1).documentId = "replacement-document";
    const response = await b.request("page.type", { target: "Search", text: "private draft", submit: true, pageTarget });
    assert.equal(response.error.code, "stale_target");
    assert.deepEqual(b.state.writes, []);
  });
}

for (const change of ["new-document", "same-document-url"]) {
  test(`${change} between validation and injection is rejected`, async () => {
    const b = browser();
    const pageTarget = await b.target();
    b.state.beforeInject = injection => {
      if (!injection.target.documentIds) return;
      if (change === "new-document") b.pages.get(1).documentId = "replacement-document";
      else b.pages.get(1).url = "https://site1.example/different-form";
    };
    const response = await b.request("page.type", { target: "Search", text: "private draft", pageTarget });
    assert.equal(response.ok, false);
    assert.deepEqual(b.state.writes, []);
  });
}

test("typing retains field matching and submit behavior on the approved page", async () => {
  const b = browser();
  const pageTarget = await b.target();
  const response = await b.request("page.type", { target: "Search", text: "hello", submit: true, pageTarget });
  assert.equal(response.ok, true);
  assert.deepEqual(b.state.writes, ["type:hello", "submit"]);
});

test("indexed actions use both document binding and element-state freshness", async () => {
  const b = browser();
  const pageTarget = await b.target();
  const stale = await b.request("page.click_index", { index: 1, state: "old", pageTarget });
  assert.equal(stale.error.code, "stale_elements");
  assert.deepEqual(b.state.writes, []);
  const valid = await b.request("page.click_index", { index: 1, state: "fixture-state", pageTarget });
  assert.equal(valid.ok, true);
  assert.deepEqual(b.state.writes, ["click:Save"]);
});

test("context exposes its exact target and a later element read refuses a tab switch", async () => {
  const b = browser();
  const response = await b.request("page.context");
  assert.equal(response.ok, true);
  assert.equal(response.result.target.documentId, "document-1");
  b.state.active = 2;
  const indexed = await b.request("page.elements", { pageTarget: response.result.target });
  assert.equal(indexed.error.code, "stale_target");
});

test("closing a named inactive tab does not retarget the current tab", async () => {
  const b = browser();
  const pageTarget = await b.target({ tabId: 2 });
  assert.equal(pageTarget.requiresActive, false);
  const response = await b.request("tab.close", { pageTarget });
  assert.equal(response.ok, true);
  assert.deepEqual(b.state.removed, [2]);
});

test("closing a tab after its URL changes is rejected", async () => {
  const b = browser();
  const pageTarget = await b.target({ tabId: 2 });
  b.pages.get(2).url = "https://another.example/";
  const response = await b.request("tab.close", { pageTarget });
  assert.equal(response.error.code, "stale_target");
  assert.deepEqual(b.state.removed, []);
});
