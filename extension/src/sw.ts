// ZEUS extension service worker. Holds one native-messaging port to com.zeus.bridge (an open
// native port keeps the MV3 service worker alive) and answers the app's browser requests.

import { pageContext, clickElement, typeInto, fillComposer, indexElements, actOnElement, scrollPage, extractText } from "./page";

const HOST = "com.zeus.bridge";
const RECONNECT_MS = 5_000;

type BridgeRequest = { id: string; type: string; params: Record<string, unknown> };
type BridgeResponse = {
  id: string;
  ok: boolean;
  result?: unknown;
  error?: { code: string; site?: string; message?: string };
};

/** A consent applies to one tab and document. A same-URL reload is a different document. */
type ActionTarget = { tabId: number; url: string; documentId?: string; requiresActive: boolean };

class BridgeFailure extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

/** The AI web apps ZEUS can hand a prompt to. They run in your own logged-in tabs. */
const ASSISTANTS: Record<string, { url: string }> = {
  chatgpt: { url: "https://chatgpt.com/" },
  claude: { url: "https://claude.ai/new" },
  dust: { url: "https://dust.tt/home" },
};

let port: chrome.runtime.Port | null = null;
let hostInfo: { version?: string } | null = null;
let lastError: string | undefined;

function connect(): void {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (error) {
    console.warn("[ZEUS] connectNative failed", error);
    setTimeout(connect, RECONNECT_MS);
    return;
  }
  port.onMessage.addListener((message: BridgeRequest | BridgeResponse) => {
    if ("ok" in message) {
      if (message.id === "hello") {
        console.info("[ZEUS] bridge connected", message.result);
        hostInfo = (message.result as { version?: string }) ?? {};
        lastError = undefined;
        void chrome.storage.local.set({ bridgeConnected: message.ok });
      }
      return;
    }
    void answer(message);
  });
  port.onDisconnect.addListener(() => {
    console.warn("[ZEUS] bridge disconnected", chrome.runtime.lastError?.message);
    port = null;
    hostInfo = null;
    lastError = chrome.runtime.lastError?.message;
    void chrome.storage.local.set({ bridgeConnected: false });
    setTimeout(connect, RECONNECT_MS);
  });
  port.postMessage({ id: "hello", type: "ping", params: {} });
}

async function answer(request: BridgeRequest): Promise<void> {
  let response: BridgeResponse;
  try {
    response = { id: request.id, ok: true, result: await handle(request) };
  } catch (error) {
    const code = error instanceof BridgeFailure ? error.code : "failed";
    response = { id: request.id, ok: false, error: { code, message: String((error as Error).message ?? error) } };
  }
  port?.postMessage(response);
}

async function handle({ type, params }: BridgeRequest): Promise<unknown> {
  switch (type) {
    case "ping":
      return { pong: true, extension: chrome.runtime.id, version: chrome.runtime.getManifest().version };

    case "tabs.list": {
      const tabs = await chrome.tabs.query({});
      return tabs.map((tab) => ({ id: tab.id, title: tab.title, url: tab.url, active: tab.active, windowId: tab.windowId }));
    }

    case "page.context": {
      const target = params.pageTarget ? await validatedTarget(params) : await captureTarget(await activeTab());
      const tab = await chrome.tabs.get(target.tabId);
      const base = { tabId: tab.id, url: target.url, title: tab.title ?? "", target };
      if (!scriptable(tab.url)) return base;
      const limit = typeof params.limit === "number" ? params.limit : 6_000;
      return { ...base, ...(await runTarget(target, pageContext, [limit, target.url])) };
    }

    // Read immediately before presenting a consent card. No page text is read here.
    case "page.target": {
      const explicit = params.tabId !== undefined || params.title !== undefined;
      const tab = explicit ? await findTab(params) : await activeTab();
      return { ...(await captureTarget(tab, !explicit)), title: tab.title ?? "" };
    }

    case "tab.open": {
      const url = requireString(params.url, "url");
      if (!/^https?:\/\//i.test(url)) throw new BridgeFailure("bad_url", "Only http and https links can be opened");
      const tab = await chrome.tabs.create({ url, active: true });
      await focus(tab);
      return { tabId: tab.id };
    }

    case "page.click": {
      const target = await validatedTarget(params, true);
      return runTarget(target, clickElement, [requireString(params.text, "text"), target.url]);
    }

    case "page.type": {
      const target = await validatedTarget(params, true);
      const field = typeof params.target === "string" ? params.target : "";
      return runTarget(target, typeInto, [field, requireString(params.text, "text"), params.submit === true, target.url]);
    }

    // Indexed actions: numbered elements and the commands that act on them by number. A number
    // from an older page state fails with "stale_elements" (see page.ts).
    case "page.elements": {
      const target = params.pageTarget ? await validatedTarget(params) : await captureTarget(await activeTab());
      const tab = await chrome.tabs.get(target.tabId);
      const base = { tabId: tab.id, url: target.url, title: tab.title ?? "", target };
      if (!scriptable(tab.url)) return { ...base, state: "", total: 0, elements: [] };
      return { ...base, ...(await runTarget(target, indexElements, [clamp(params.max, 1, 150, 150), target.url])) };
    }

    case "page.click_index": {
      const target = await validatedTarget(params, true);
      return runTarget(target, actOnElement, ["click", requireIndex(params.index), stateOf(params), {}, target.url]);
    }

    case "page.type_index": {
      const target = await validatedTarget(params, true);
      const text = typeof params.text === "string" ? params.text : "";
      return runTarget(target, actOnElement, ["type", requireIndex(params.index), stateOf(params), { text, submit: params.submit === true }, target.url]);
    }

    case "page.select": {
      const target = await validatedTarget(params, true);
      const option = requireString(params.option, "option");
      return runTarget(target, actOnElement, ["select", requireIndex(params.index), stateOf(params), { option }, target.url]);
    }

    case "page.scroll": {
      const tab = await activeTab();
      ensureScriptable(tab);
      if (params.index !== undefined) {
        return run(tab.id!, actOnElement, ["scroll", requireIndex(params.index), stateOf(params), {}]);
      }
      const direction = params.direction === "up" ? "up" : "down";
      return run(tab.id!, scrollPage, [direction, clamp(params.pages, 0.1, 10, 1)]);
    }

    case "page.extract": {
      const tab = await activeTab();
      ensureScriptable(tab);
      return { tabId: tab.id, ...(await run(tab.id!, extractText, [Math.round(clamp(params.limit, 200, 20_000, 4_000))])) };
    }

    case "tab.back":
    case "tab.forward": {
      const target = await validatedTarget(params);
      try {
        if (type === "tab.back") await chrome.tabs.goBack(target.tabId);
        else await chrome.tabs.goForward(target.tabId);
      } catch {
        throw new BridgeFailure("no_history", type === "tab.back" ? "There's no earlier page in this tab." : "There's no later page in this tab.");
      }
      await loaded(target.tabId);
      return { tabId: target.tabId };
    }

    case "tab.find": {
      const tab = await findTab(params);
      return { tabId: tab.id, title: tab.title ?? "", url: tab.url ?? "" };
    }

    case "tab.switch": {
      const tab = await findTab(params);
      await chrome.tabs.update(tab.id!, { active: true });
      await focus(tab);
      return { tabId: tab.id, title: tab.title ?? "", url: tab.url ?? "" };
    }

    case "tab.close": {
      const target = await validatedTarget(params);
      await chrome.tabs.remove(target.tabId);
      return { closed: target.tabId };
    }

    case "ai.ask": {
      const which = requireString(params.which, "which").toLowerCase();
      const assistant = ASSISTANTS[which];
      if (!assistant) throw new BridgeFailure("unknown_assistant", `No assistant called ${which}`);
      const prompt = typeof params.prompt === "string" ? params.prompt : "";
      const tab = await chrome.tabs.create({ url: assistant.url, active: true });
      await focus(tab);
      await loaded(tab.id!);
      if (!prompt) return { tabId: tab.id, filled: false };
      const result = await run(tab.id!, fillComposer, [prompt, params.send !== false]);
      return { tabId: tab.id, ...result };
    }

    default:
      throw new BridgeFailure("unknown_type", type);
  }
}

// MARK: helpers

async function captureTarget(tab: chrome.tabs.Tab, requiresActive = true): Promise<ActionTarget> {
  if (tab.id === undefined || !tab.url) throw new BridgeFailure("stale_target", "The selected tab is no longer available.");
  if (!scriptable(tab.url)) return { tabId: tab.id, url: tab.url, requiresActive };
  const [frame] = await chrome.scripting.executeScript({
    target: { tabId: tab.id }, func: () => location.href,
  });
  if (!frame?.documentId || frame.result !== tab.url) {
    throw new BridgeFailure("stale_target", "The page changed while Zeus was looking at it. Try again.");
  }
  return { tabId: tab.id, url: tab.url, documentId: frame.documentId, requiresActive };
}

/** Validate after approval, without resolving a different active tab as the new target. */
async function validatedTarget(params: Record<string, unknown>, requiresDocument = false): Promise<ActionTarget> {
  const raw = params.pageTarget as Partial<ActionTarget> | undefined;
  if (!raw || !Number.isInteger(raw.tabId) || typeof raw.url !== "string" || !raw.url ||
      typeof raw.requiresActive !== "boolean" || (requiresDocument && (typeof raw.documentId !== "string" || !raw.documentId))) {
    throw new BridgeFailure("stale_target", "Read page.target before approving this action. Nothing was changed.");
  }
  const target = raw as ActionTarget;
  let tab: chrome.tabs.Tab;
  try { tab = await chrome.tabs.get(target.tabId); }
  catch { throw new BridgeFailure("stale_target", "The approved tab was closed. Nothing was changed."); }
  if (tab.url !== target.url || (target.requiresActive && (await activeTab()).id !== target.tabId)) {
    throw new BridgeFailure("stale_target", "The active tab or approved page changed. Nothing was changed.");
  }
  if (requiresDocument) ensureScriptable(tab);
  if (target.documentId) {
    // Same URL with a new document (reload, back/forward) must not inherit the approval.
    const current = await captureTarget(tab, target.requiresActive);
    if (current.documentId !== target.documentId) {
      throw new BridgeFailure("stale_target", "The approved page reloaded. Nothing was changed.");
    }
  }
  return target;
}

async function runTarget<A extends unknown[], R>(target: ActionTarget, func: (...args: A) => R | Promise<R>, args: A): Promise<Awaited<R>> {
  if (!target.documentId) throw new BridgeFailure("stale_target", "The approved document is unavailable. Nothing was changed.");
  // Chrome resolves documentIds at injection time, so a navigation between validation and injection
  // cannot redirect the write to a replacement document. The function also checks same-document URLs.
  const frames = await chrome.scripting.executeScript({
    target: { tabId: target.tabId, documentIds: [target.documentId] }, func, args,
  });
  const frame = frames[0];
  if (!frame || frame.documentId !== target.documentId) {
    throw new BridgeFailure("stale_target", "The approved document is no longer available. Nothing was changed.");
  }
  return checkedResult(frame.result as Awaited<R>);
}

async function activeTab(): Promise<chrome.tabs.Tab> {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) throw new BridgeFailure("no_tab", "No active Chrome tab");
  return tab;
}

function scriptable(url?: string): boolean {
  return !!url && /^https?:\/\//i.test(url) && !/^https:\/\/chromewebstore\.google\.com/i.test(url);
}

function ensureScriptable(tab: chrome.tabs.Tab): void {
  if (!scriptable(tab.url)) throw new BridgeFailure("not_scriptable", "Chrome doesn't let extensions act on this page");
}

async function focus(tab: chrome.tabs.Tab): Promise<void> {
  if (tab.windowId !== undefined) await chrome.windows.update(tab.windowId, { focused: true });
}

/** Resolves when the tab finishes loading (or after 15 s). */
function loaded(tabId: number): Promise<void> {
  return new Promise((resolve) => {
    const done = () => {
      chrome.tabs.onUpdated.removeListener(listener);
      clearTimeout(timer);
      resolve();
    };
    const listener = (id: number, info: chrome.tabs.TabChangeInfo) => {
      if (id === tabId && info.status === "complete") done();
    };
    const timer = setTimeout(done, 15_000);
    chrome.tabs.onUpdated.addListener(listener);
    void chrome.tabs.get(tabId).then((tab) => {
      if (tab.status === "complete") done();
    });
  });
}

async function run<A extends unknown[], R>(tabId: number, func: (...args: A) => R | Promise<R>, args: A): Promise<Awaited<R>> {
  const [frame] = await chrome.scripting.executeScript({ target: { tabId }, func, args });
  return checkedResult(frame?.result as Awaited<R>);
}

function checkedResult<R>(value: R): R {
  const result = value as (R & { error?: { code: string; message: string } }) | undefined;
  if (result && typeof result === "object" && "error" in result && result.error) {
    throw new BridgeFailure(result.error.code, result.error.message);
  }
  return result as R;
}

/** A tab by id, or by title (exact, then contains), then by URL containing the text. */
async function findTab(params: Record<string, unknown>): Promise<chrome.tabs.Tab> {
  const tabs = (await chrome.tabs.query({})).filter((tab) => tab.id !== undefined);
  let found: chrome.tabs.Tab | undefined;
  if (typeof params.tabId === "number") {
    found = tabs.find((tab) => tab.id === params.tabId);
  } else {
    const wanted = requireString(params.title, "tabId or title").trim().toLowerCase();
    const title = (tab: chrome.tabs.Tab) => (tab.title ?? "").toLowerCase();
    found = tabs.find((tab) => title(tab) === wanted) ??
      tabs.find((tab) => title(tab).includes(wanted)) ??
      tabs.find((tab) => (tab.url ?? "").toLowerCase().includes(wanted));
  }
  if (!found) throw new BridgeFailure("not_found", "I couldn't find that tab");
  return found;
}

function requireIndex(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) throw new BridgeFailure("bad_request", "Missing element index");
  return value;
}

function stateOf(params: Record<string, unknown>): string {
  return typeof params.state === "string" ? params.state : "";
}

function clamp(value: unknown, min: number, max: number, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || !value.trim()) throw new BridgeFailure("bad_request", `Missing ${name}`);
  return value;
}

/** The popup asks for status, or to reconnect now instead of waiting for the retry. */
chrome.runtime.onMessage.addListener((message: { type?: string }, _sender, sendResponse) => {
  if (message.type !== "status" && message.type !== "reconnect") return;
  const reply = () => sendResponse(
    hostInfo
      ? { connected: true, detail: `Bridge ${hostInfo.version ?? ""} is running.` }
      : { connected: false, detail: lastError ? `Chrome says: ${lastError}` : undefined }
  );
  if (message.type === "reconnect" && !port) {
    connect();
    setTimeout(reply, 800);
    return true;
  }
  reply();
  return undefined;
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
