import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { readFileSync } from "node:fs";
import { build } from "esbuild";

// The production service worker and its injected media functions, with Chrome replaced only at the extension
// boundary. Pages are vm contexts with fake media elements: no real tab, account, audio or capture is used.
const compiled = await build({ entryPoints: ["src/sw.ts"], bundle: true, format: "iife", write: false });
const workerSource = compiled.outputFiles[0].text;
const manifest = JSON.parse(readFileSync("manifest.json", "utf8"));

const plain = value => JSON.parse(JSON.stringify(value));
const macrotask = () => new Promise(resolve => setImmediate(resolve));

function ranges(start, end) {
  return { length: 1, start: () => start, end: () => end };
}

function element(overrides = {}) {
  const el = {
    srcObject: null, currentSrc: "https://cdn.example/track.mp4", muted: false, volume: 1, paused: false,
    duration: 200, currentTime: 10, playbackRate: 1, seekable: ranges(0, 200),
    rect: { left: 0, top: 0, right: 640, bottom: 360, width: 640, height: 360 },
    calls: [],
    getBoundingClientRect() { return this.rect; },
    play() { this.calls.push("play"); if (this.refuse) return Promise.reject(new Error("NotAllowedError")); this.paused = false; return Promise.resolve(); },
    pause() { this.calls.push("pause"); this.paused = true; },
    ...overrides,
  };
  return el;
}

function browser() {
  let receive;
  let nextID = 0;
  const pending = new Map();
  const timers = [];
  const state = { active: 1, injections: [], hold: undefined, gate: new Map() };
  const pages = new Map();

  function addPage(id, options = {}) {
    const page = {
      id, url: `https://site${id}.example/watch`, documentId: `document-${id}`, title: `Site ${id}`,
      audible: true, incognito: false, discarded: false, elements: [], metadata: null, playbackState: "playing",
      ...options,
    };
    page.context = vm.createContext({
      location: { href: page.url }, innerWidth: 1280, innerHeight: 720,
      get document() { return { querySelectorAll: () => page.elements, title: page.title }; },
      get navigator() { return { mediaSession: { metadata: page.metadata, playbackState: page.playbackState } }; },
    });
    pages.set(id, page);
    return page;
  }

  const tab = id => {
    const page = pages.get(id);
    if (!page) throw new Error("No tab");
    return { id, url: page.url, title: page.title, active: state.active === id, status: "complete", audible: page.audible,
             incognito: page.incognito, discarded: page.discarded, windowId: 1 };
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
    runtime: {
      connectNative: () => port, getManifest: () => manifest, id: "fixture",
      onMessage: { addListener() {} }, onStartup: { addListener() {} }, onInstalled: { addListener() {} },
    },
    storage: { local: { set: async () => {} } },
    tabs: {
      get: async id => tab(id),
      query: async query => {
        if (query.active) return [tab(state.active)];
        const all = [...pages.keys()].map(tab);
        return query.audible ? all.filter(item => item.audible) : all;
      },
      onUpdated: { addListener() {}, removeListener() {} },
    },
    scripting: {
      executeScript: async injection => {
        const page = pages.get(injection.target.tabId);
        state.injections.push({ tabId: injection.target.tabId, name: injection.func.name, args: injection.args, world: injection.world });
        const gate = state.gate.get(injection.target.tabId);
        if (gate && injection.func.name === "mediaState") return gate(page);
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

  vm.runInNewContext(workerSource, {
    chrome, URL, console: { warn() {}, info() {} },
    setTimeout: fn => { timers.push(fn); return timers.length; },
    clearTimeout: id => { timers[id - 1] = null; },
  });

  function fire() {
    for (const fn of timers.splice(0)) fn?.();
  }

  function request(type, params = {}) {
    const id = String(++nextID);
    const result = new Promise(resolve => pending.set(id, resolve));
    receive({ id, type, params });
    return result;
  }

  /** Sends a request and lets every per-tab time budget run out once the work that can finish has finished. */
  async function ask(type, params = {}) {
    let done = false;
    const result = request(type, params);
    result.then(() => { done = true; });
    for (let turn = 0; turn < 20 && !done; turn++) {
      await macrotask();
      if (!done) fire();
    }
    assert.equal(done, true, `${type} never answered`);
    return plain(await result);
  }

  async function target(tabId = 1) {
    const page = pages.get(tabId);
    return { tabId, url: page.url, documentId: page.documentId, requiresActive: false };
  }

  return { state, pages, addPage, request, ask, fire, target };
}

function playingPage(b, id = 1, options = {}) {
  const content = element(options.element);
  return Object.assign(b.addPage(id, { elements: [content], metadata: { title: "Song", artist: "Band", album: "Record", artwork: [] }, ...options.page }), { content });
}

test("an audible tab with media is reported with its element and metadata", async () => {
  const b = browser();
  const page = playingPage(b);
  const reply = await b.ask("media.state", { known: [] });
  assert.equal(reply.ok, true);
  const [item] = reply.result.items;
  assert.equal(item.tabId, 1);
  assert.equal(item.documentId, "document-1");
  assert.equal(item.url, page.url);
  assert.equal(item.title, "Song");
  assert.equal(item.artist, "Band");
  assert.equal(item.album, "Record");
  assert.equal(item.audible, true);
  assert.equal(item.paused, false);
  assert.equal(item.currentTime, 10);
  assert.equal(item.duration, 200);
  assert.equal(item.playbackRate, 1);
  assert.equal(item.seekable, true);
  assert.match(item.fingerprint, /^[0-9a-f]{8}$/);
  assert.equal(JSON.stringify(item).includes("cdn.example"), false, "the media address is never sent, only its hash");
});

test("a tab with no media element gives no item", async () => {
  const b = browser();
  b.addPage(1, { elements: [] });
  const reply = await b.ask("media.state", { known: [] });
  assert.deepEqual(reply.result.items, []);
});

test("a page whose only media carries a MediaStream (a call) gives no item", async () => {
  const b = browser();
  b.addPage(1, { elements: [element({ srcObject: { id: "stream" } }), element({ srcObject: {}, currentSrc: "" })] });
  const reply = await b.ask("media.state", { known: [] });
  assert.deepEqual(reply.result.items, []);
});

test("a muted or silent element, or one with no source, is never chosen", async () => {
  const b = browser();
  b.addPage(1, { elements: [element({ muted: true }), element({ volume: 0 }), element({ currentSrc: "" })] });
  assert.deepEqual((await b.ask("media.state", { known: [] })).result.items, []);
});

test("an ad and a content element: the larger one that plays is chosen", async () => {
  const b = browser();
  const ad = element({ currentSrc: "https://ads.example/ad.mp4", duration: 15, rect: { left: 0, top: 0, right: 300, bottom: 250, width: 300, height: 250 } });
  const content = element({ currentSrc: "https://cdn.example/film.mp4", duration: 5400, rect: { left: 0, top: 0, right: 1280, bottom: 720, width: 1280, height: 720 } });
  b.addPage(1, { elements: [ad, content] });
  const first = (await b.ask("media.state", { known: [] })).result.items[0];
  const alone = browser();
  alone.addPage(1, { elements: [content] });
  assert.equal(first.fingerprint, (await alone.ask("media.state", { known: [] })).result.items[0].fingerprint);
  assert.equal(first.duration, 5400);
});

test("a playing element beats a larger paused one, and a longer one wins a tie in size", async () => {
  const b = browser();
  const paused = element({ currentSrc: "https://cdn.example/big.mp4", paused: true, duration: 90 });
  const playing = element({ currentSrc: "https://cdn.example/small.mp4", duration: 30, rect: { left: 0, top: 0, right: 100, bottom: 100, width: 100, height: 100 } });
  b.addPage(1, { elements: [paused, playing] });
  const item = (await b.ask("media.state", { known: [] })).result.items[0];
  assert.equal(item.paused, false);
  assert.equal(item.duration, 30);
  const tie = browser();
  tie.addPage(1, { elements: [element({ currentSrc: "https://a.example/1.mp3", duration: 60 }), element({ currentSrc: "https://a.example/2.mp3", duration: 300 })] });
  assert.equal((await tie.ask("media.state", { known: [] })).result.items[0].duration, 300);
});

test("without metadata the tab title is used and there is no artist", async () => {
  const b = browser();
  b.addPage(1, { title: "Live set - Example", elements: [element()], metadata: null });
  const [item] = (await b.ask("media.state", { known: [] })).result.items;
  assert.equal(item.title, "Live set - Example");
  assert.equal(item.artist, "");
  assert.equal(item.album, "");
});

test("a live stream reports no length and cannot be sought", async () => {
  const b = browser();
  b.addPage(1, { elements: [element({ duration: Infinity, seekable: { length: 0 } })], metadata: { title: "Radio", artist: "", album: "" } });
  const [item] = (await b.ask("media.state", { known: [] })).result.items;
  assert.equal(item.duration, null);
  assert.equal(item.seekable, false);
});

test("text is capped and one https cover is picked, never data, blob or http", async () => {
  const b = browser();
  const long = "x".repeat(900);
  b.addPage(1, {
    elements: [element()],
    metadata: { title: long, artist: long, album: long, artwork: [
      { src: "data:image/png;base64,AAAA", sizes: "999x999" },
      { src: "blob:https://site1.example/1", sizes: "998x998" },
      { src: "http://img.example/big.jpg", sizes: "997x997" },
      { src: "/small.jpg", sizes: "64x64" },
      { src: "https://img.example/large.jpg", sizes: "512x512" },
    ] },
  });
  const [item] = (await b.ask("media.state", { known: [] })).result.items;
  assert.equal(item.title.length, 300);
  assert.equal(item.artist.length, 300);
  assert.equal(item.album.length, 300);
  assert.equal(item.artworkURL, "https://img.example/large.jpg");
  const small = browser();
  small.addPage(1, { elements: [element()], metadata: { title: "T", artist: "", album: "", artwork: [{ src: "/c.jpg", sizes: "64x64" }, { src: "https://img.example/" + "a".repeat(2100), sizes: "9999x9999" }] } });
  assert.equal((await small.ask("media.state", { known: [] })).result.items[0].artworkURL, "https://site1.example/c.jpg");
});

test("a private window and a discarded tab are skipped", async () => {
  const b = browser();
  playingPage(b, 1, { page: { incognito: true } });
  playingPage(b, 2, { page: { discarded: true } });
  playingPage(b, 3);
  const reply = await b.ask("media.state", { known: [] });
  assert.deepEqual(reply.result.items.map(item => item.tabId), [3]);
  assert.equal(b.state.injections.filter(i => i.tabId === 1 || i.tabId === 2).length, 0, "nothing is injected into them");
});

test("a page written to disk and other non-web tabs are never read", async () => {
  const b = browser();
  for (const [id, url] of [[1, "file:///Users/me/saved/page.html"], [2, "chrome://settings"], [3, "chrome-extension://abc/page.html"], [4, "https://chromewebstore.google.com/detail/x"]]) {
    playingPage(b, id, { page: { url } });
  }
  const reply = await b.ask("media.state", { known: [] });
  assert.deepEqual(reply.result.items, []);
  assert.equal(b.state.injections.length, 0);
});

test("at most four tabs are read", async () => {
  const b = browser();
  for (let id = 1; id <= 7; id++) playingPage(b, id);
  const reply = await b.ask("media.state", { known: [] });
  assert.equal(reply.result.items.length, 4);
});

test("a throwing tab and a never-resolving tab still leave a reply for the healthy one", async () => {
  const b = browser();
  playingPage(b, 1);
  playingPage(b, 2);
  playingPage(b, 3);
  b.state.gate.set(1, () => { throw new Error("frame removed"); });
  b.state.gate.set(2, () => new Promise(() => {}));
  const reply = await b.ask("media.state", { known: [] });
  assert.equal(reply.ok, true);
  assert.deepEqual(reply.result.items.map(item => item.tabId), [3]);
  assert.deepEqual(reply.result.gone, [], "a slow or failed tab is left out, never reported gone");
});

test("a media.state during another gets the last reply marked stale", async () => {
  const b = browser();
  playingPage(b, 1);
  const first = await b.ask("media.state", { known: [] });
  assert.equal(first.result.stale, undefined);
  b.state.gate.set(1, () => new Promise(() => {}));
  const slow = b.request("media.state", { known: [] });
  await macrotask();
  const second = plain(await b.request("media.state", { known: [] }));
  assert.equal(second.ok, true);
  assert.equal(second.result.stale, true);
  assert.deepEqual(second.result.items.map(item => item.tabId), [1], "it carries the last reply");
  b.fire();
  await slow;
  b.state.gate.delete(1);
  assert.equal((await b.ask("media.state", { known: [] })).result.stale, undefined, "single flight is released");
});

test("a known tab that is paused is reported even when it is no longer audible", async () => {
  const b = browser();
  playingPage(b, 1, { page: { audible: false }, element: { paused: true } });
  assert.deepEqual((await b.ask("media.state", { known: [] })).result.items, []);
  const reply = await b.ask("media.state", { known: [{ tabId: 1, documentId: "document-1" }] });
  assert.equal(reply.result.items.length, 1);
  assert.equal(reply.result.items[0].paused, true);
  assert.equal(reply.result.items[0].audible, false);
});

test("a closed or reloaded known tab is reported gone", async () => {
  const b = browser();
  playingPage(b, 1);
  const known = [{ tabId: 1, documentId: "stale-document" }, { tabId: 9, documentId: "closed" }];
  const reply = await b.ask("media.state", { known });
  assert.deepEqual(reply.result.gone.sort((x, y) => x.tabId - y.tabId), [{ tabId: 1, documentId: "stale-document" }, { tabId: 9, documentId: "closed" }]);
  assert.equal(reply.result.items.length, 1, "the new document is reported as its own item");
});

test("a known private tab is dropped, not read", async () => {
  const b = browser();
  playingPage(b, 1, { page: { incognito: true, audible: false } });
  const reply = await b.ask("media.state", { known: [{ tabId: 1, documentId: "document-1" }] });
  assert.deepEqual(reply.result.items, []);
  assert.deepEqual(reply.result.gone, [{ tabId: 1, documentId: "document-1" }]);
  assert.equal(b.state.injections.length, 0);
});

test("only four known tabs are honoured", async () => {
  const b = browser();
  for (let id = 1; id <= 6; id++) playingPage(b, id, { page: { audible: false } });
  const known = [1, 2, 3, 4, 5, 6].map(tabId => ({ tabId, documentId: `document-${tabId}` }));
  assert.equal((await b.ask("media.state", { known })).result.items.length, 4);
});

// MARK: commands

async function command(b, action, extra = {}, tabId = 1) {
  const item = (await b.ask("media.state", { known: [{ tabId, documentId: `document-${tabId}` }] })).result.items.find(i => i.tabId === tabId);
  return b.ask("media.command", { action, pageTarget: await b.target(tabId), fingerprint: item.fingerprint, ...extra });
}

test("play, pause and seek reach the captured document", async () => {
  const b = browser();
  const page = playingPage(b, 1, { element: { paused: true } });
  assert.equal((await command(b, "play")).ok, true);
  assert.deepEqual(page.content.calls, ["play"]);
  assert.equal((await command(b, "pause")).ok, true);
  assert.deepEqual(page.content.calls, ["play", "pause"]);
  const seek = await command(b, "seek", { seconds: 60 });
  assert.equal(seek.ok, true);
  assert.equal(page.content.currentTime, 60);
});

test("a seek stays inside the seekable range and short of the end", async () => {
  const b = browser();
  const page = playingPage(b);
  await command(b, "seek", { seconds: 9999 });
  assert.equal(page.content.currentTime, 199.5);
  await command(b, "seek", { seconds: -20 });
  assert.equal(page.content.currentTime, 0);
  page.content.seekable = ranges(30, 100);
  await command(b, "seek", { seconds: 5 });
  assert.equal(page.content.currentTime, 30);
});

test("a seek with no number is a bad request and changes nothing", async () => {
  const b = browser();
  const page = playingPage(b);
  const before = page.content.currentTime;
  const reply = await command(b, "seek", { seconds: "soon" });
  assert.equal(reply.ok, false);
  assert.equal(reply.error.code, "bad_request");
  assert.equal(page.content.currentTime, before);
});

test("a play the page refuses is blocked_by_page", async () => {
  const b = browser();
  const page = playingPage(b, 1, { element: { paused: true, refuse: true } });
  const reply = await command(b, "play");
  assert.equal(reply.ok, false);
  assert.equal(reply.error.code, "blocked_by_page");
  assert.deepEqual(page.content.calls, ["play"]);
});

test("a changed fingerprint, a reload, a navigation or a closed tab is stale_target and nothing is touched", async () => {
  const cases = {
    "changed element": (b, page) => { page.content.currentSrc = "https://cdn.example/other.mp4"; },
    "reload": (b, page) => { page.documentId = "document-new"; },
    "navigation": (b, page) => { page.url = "https://site1.example/next"; },
    "closed": (b, page) => { b.pages.delete(1); },
  };
  for (const [name, change] of Object.entries(cases)) {
    for (const action of ["play", "pause", "seek"]) {
      const b = browser();
      const page = playingPage(b);
      const item = (await b.ask("media.state", { known: [] })).result.items[0];
      const pageTarget = await b.target();
      const content = page.content;
      change(b, page);
      const reply = await b.ask("media.command", { action, seconds: 30, pageTarget, fingerprint: item.fingerprint });
      assert.equal(reply.ok, false, `${name} ${action}`);
      assert.equal(reply.error.code, "stale_target", `${name} ${action}`);
      assert.deepEqual(content.calls, [], `${name} ${action}`);
      assert.equal(content.currentTime, 10, `${name} ${action}`);
    }
  }
});

test("a command whose fingerprint belongs to another element fails the same way", async () => {
  const b = browser();
  const page = playingPage(b);
  const reply = await b.ask("media.command", { action: "pause", pageTarget: await b.target(), fingerprint: "00000000" });
  assert.equal(reply.error.code, "stale_target");
  assert.deepEqual(page.content.calls, []);
});

test("next and previous are not_supported before anything is injected", async () => {
  const b = browser();
  const page = playingPage(b);
  const pageTarget = await b.target();
  for (const action of ["next", "previous"]) {
    const reply = await b.ask("media.command", { action, pageTarget, fingerprint: "ab12cd34" });
    assert.equal(reply.ok, false);
    assert.equal(reply.error.code, "not_supported");
  }
  assert.equal(b.state.injections.length, 0);
  assert.deepEqual(page.content.calls, []);
});

test("an unknown action is a bad request", async () => {
  const b = browser();
  playingPage(b);
  const reply = await b.ask("media.command", { action: "rewind", pageTarget: await b.target(), fingerprint: "ab12cd34" });
  assert.equal(reply.error.code, "bad_request");
  assert.equal(b.state.injections.length, 0);
});

test("a command without a page target fails closed", async () => {
  const b = browser();
  const page = playingPage(b);
  for (const params of [{ action: "pause", fingerprint: "ab12cd34" }, { action: "pause", pageTarget: { tabId: 1, url: page.url, requiresActive: false }, fingerprint: "ab12cd34" }]) {
    const reply = await b.ask("media.command", params);
    assert.equal(reply.error.code, "stale_target");
  }
  assert.deepEqual(page.content.calls, []);
});

test("a background tab can be controlled", async () => {
  const b = browser();
  const page = playingPage(b, 2);
  playingPage(b, 1);
  b.state.active = 1;
  const reply = await command(b, "pause", {}, 2);
  assert.equal(reply.ok, true);
  assert.deepEqual(page.content.calls, ["pause"]);
});

test("a private window is never controlled", async () => {
  const b = browser();
  const page = playingPage(b);
  const item = (await b.ask("media.state", { known: [] })).result.items[0];
  const pageTarget = await b.target();
  page.incognito = true;
  const reply = await b.ask("media.command", { action: "pause", pageTarget, fingerprint: item.fingerprint });
  assert.equal(reply.ok, false);
  assert.equal(reply.error.code, "stale_target");
  assert.deepEqual(page.content.calls, []);
});

test("a command is never run in the page's own world", async () => {
  const b = browser();
  playingPage(b);
  await command(b, "pause");
  for (const injection of b.state.injections) assert.notEqual(injection.world, "MAIN");
});

test("the extension reports the version media needs", async () => {
  const b = browser();
  const reply = await b.ask("ping");
  assert.equal(reply.result.version, manifest.version);
  const [major, minor] = manifest.version.split(".").map(Number);
  assert.ok(major > 0 || minor >= 5, "0.5.0 or later");
});
