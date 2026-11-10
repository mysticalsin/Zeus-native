// Functions injected into pages with chrome.scripting.executeScript. Each one is serialized on
// its own, so it must be self-contained: no imports and no references to anything outside it.

type Failure = { error: { code: string; message: string } };

/** Title, URL, selection, visible text and the labels of things you can click. */
export function pageContext(limit: number, expectedURL?: string) {
  if (expectedURL && location.href !== expectedURL) {
    return { error: { code: "stale_target", message: "The approved page navigated. Nothing was changed." } };
  }
  const clean = (text: string) => text.replace(/\s+/g, " ").trim();
  const visible = (el: Element) => {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && getComputedStyle(el).visibility !== "hidden";
  };
  const controls = Array.from(document.querySelectorAll("a[href], button, [role=button], input[type=submit], summary"))
    .filter(visible)
    .map((el) => clean(el.getAttribute("aria-label") || (el as HTMLElement).innerText || el.getAttribute("title") || ""))
    .filter((label, index, all) => label.length > 0 && label.length < 60 && all.indexOf(label) === index)
    .slice(0, 40);
  return {
    url: location.href,
    title: document.title,
    selection: clean(String(getSelection() ?? "")).slice(0, 2_000) || undefined,
    text: clean(document.body?.innerText ?? "").slice(0, limit),
    controls,
  };
}

/** Clicks the visible control whose label matches `text` (exact first, then contains). */
export function clickElement(text: string, expectedURL?: string): { clicked: string } | Failure {
  if (expectedURL && location.href !== expectedURL) {
    return { error: { code: "stale_target", message: "The approved page navigated. Nothing was changed." } };
  }
  const clean = (value: string) => value.replace(/\s+/g, " ").trim().toLowerCase();
  const wanted = clean(text);
  const candidates = Array.from(
    document.querySelectorAll<HTMLElement>("a[href], button, [role=button], [role=link], [role=tab], [role=menuitem], input[type=submit], input[type=button], summary, label")
  ).filter((el) => {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && !(el as HTMLButtonElement).disabled;
  });
  const label = (el: HTMLElement) =>
    clean(el.getAttribute("aria-label") || el.innerText || (el as HTMLInputElement).value || el.getAttribute("title") || "");
  const match = candidates.find((el) => label(el) === wanted) ?? candidates.find((el) => label(el).includes(wanted));
  if (!match) return { error: { code: "not_found", message: `Nothing called "${text}" to click on this page` } };
  match.scrollIntoView({ block: "center" });
  match.click();
  return { clicked: label(match) };
}

/** Types into the field matching `target` (label, placeholder, name), or the focused field. */
export function typeInto(target: string, text: string, submit: boolean, expectedURL?: string): { typed: string; submitted: boolean } | Failure {
  if (expectedURL && location.href !== expectedURL) {
    return { error: { code: "stale_target", message: "The approved page navigated. Nothing was changed." } };
  }
  const clean = (value: string) => value.replace(/\s+/g, " ").trim().toLowerCase();
  const editable = (el: Element | null): el is HTMLElement =>
    !!el && (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || (el as HTMLElement).isContentEditable);
  const describe = (el: HTMLElement) => {
    const labelled = el.id ? document.querySelector(`label[for="${CSS.escape(el.id)}"]`) : null;
    return clean([
      el.getAttribute("aria-label"), el.getAttribute("placeholder"), el.getAttribute("name"),
      labelled?.textContent, el.closest("label")?.textContent,
    ].filter(Boolean).join(" "));
  };
  const fields = Array.from(document.querySelectorAll<HTMLElement>("input, textarea, [contenteditable=true], [role=textbox]"))
    .filter((el) => {
      const rect = el.getBoundingClientRect();
      const input = el as HTMLInputElement;
      return rect.width > 0 && rect.height > 0 && !input.disabled && !input.readOnly &&
        !(el instanceof HTMLInputElement && ["hidden", "checkbox", "radio", "submit", "button", "file"].includes(el.type));
    });
  const wanted = clean(target);
  const field = wanted
    ? fields.find((el) => describe(el).includes(wanted))
    : editable(document.activeElement) ? (document.activeElement as HTMLElement) : fields[0];
  if (!field) return { error: { code: "not_found", message: target ? `No field called "${target}"` : "No text field on this page" } };

  // Passwords and card details are always left to you.
  const autocomplete = field.getAttribute("autocomplete") ?? "";
  if ((field instanceof HTMLInputElement && field.type === "password") || /cc-|password/.test(autocomplete)) {
    return { error: { code: "sensitive_field", message: "That's a password or payment field. Please type it yourself." } };
  }

  field.focus();
  if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) {
    const proto = field instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
    Object.getOwnPropertyDescriptor(proto, "value")?.set?.call(field, text);
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  } else {
    document.execCommand("selectAll");
    document.execCommand("insertText", false, text);
  }

  let submitted = false;
  if (submit) {
    const form = field.closest("form");
    if (form) {
      form.requestSubmit();
    } else {
      for (const type of ["keydown", "keypress", "keyup"]) {
        field.dispatchEvent(new KeyboardEvent(type, { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }));
      }
    }
    submitted = true;
  }
  return { typed: describe(field) || field.tagName.toLowerCase(), submitted };
}

/** Waits for an AI chat composer (ChatGPT, Claude, Dust), fills in the prompt and sends it. */
export async function fillComposer(prompt: string, send: boolean): Promise<{ filled: boolean; sent: boolean } | Failure> {
  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
  const visible = (el: Element | null): el is HTMLElement => {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const composerSelectors = [
    "#prompt-textarea",
    "div.ProseMirror[contenteditable=true]",
    "[contenteditable=true][role=textbox]",
    "div.tiptap[contenteditable=true]",
    "[contenteditable=true]",
    "textarea",
  ];
  let composer: HTMLElement | null = null;
  const blocked = () => /just a moment|security verification|verify you are human/i.test(document.title + " " + (document.body?.innerText ?? "").slice(0, 2_000));
  for (let waited = 0; waited < 15_000 && !composer; waited += 250) {
    if (waited >= 4_000 && blocked()) break;
    if (waited >= 6_000 && /\b(sign in|log in)\b/i.test((document.body?.innerText ?? "").slice(0, 3_000))) break;
    for (const selector of composerSelectors) {
      const found = Array.from(document.querySelectorAll(selector)).find(visible);
      if (found) {
        composer = found as HTMLElement;
        break;
      }
    }
    if (!composer) await sleep(250);
  }
  if (!composer) {
    const text = (document.title + " " + (document.body?.innerText ?? "")).toLowerCase();
    if (/just a moment|security verification|verify you are human|checking your browser/.test(text)) {
      return { error: { code: "challenge", message: `${location.hostname} is showing a security check. Finish it in Chrome, then ask me again.` } };
    }
    if (/\b(sign in|log in|sign up)\b/.test(text)) {
      return { error: { code: "signed_out", message: `You're signed out of ${location.hostname} in Chrome. Sign in, then ask me again.` } };
    }
    return { error: { code: "no_composer", message: `I couldn't find the message box on ${location.hostname}.` } };
  }

  composer.focus();
  if (composer instanceof HTMLTextAreaElement) {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set?.call(composer, prompt);
    composer.dispatchEvent(new Event("input", { bubbles: true }));
  } else {
    document.execCommand("selectAll");
    document.execCommand("insertText", false, prompt);
  }
  if (!send) return { filled: true, sent: false };

  const sendSelectors = [
    "[data-testid=send-button]",
    "button[aria-label='Send message']",
    "button[aria-label*='Send' i]",
    "button[type=submit]",
  ];
  for (let waited = 0; waited < 5_000; waited += 200) {
    await sleep(200);
    for (const selector of sendSelectors) {
      const button = Array.from(document.querySelectorAll<HTMLButtonElement>(selector))
        .find((el) => visible(el) && !el.disabled && el.getAttribute("aria-disabled") !== "true");
      if (button) {
        button.click();
        return { filled: true, sent: true };
      }
    }
  }
  composer.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }));
  return { filled: true, sent: true };
}

// MARK: indexed elements
// The idea of numbering a page's interactive elements and acting on them by number comes from
// browser-use (MIT, Gregor Zunic). The numbered elements stay in this extension's isolated world
// (it lives as long as the document), under a page-state id. A number sent with another id, after
// a navigation, or after the page changed a lot, fails with "stale_elements" instead of hitting
// whatever now sits at that number.

/** A number from an older element list. Nothing was touched. */
export type StaleFailure = { error: { code: "stale_elements"; message: string } };

export type IndexedElement = {
  index: number;
  role: string;
  text: string;
  href?: string;
  inViewport: boolean;
  options?: string[];
};

/** Numbers the visible interactive elements, those on screen first, at most `max`. */
export function indexElements(max: number, expectedURL?: string): { state: string; total: number; elements: IndexedElement[] } | Failure {
  if (expectedURL && location.href !== expectedURL) {
    return { error: { code: "stale_target", message: "The approved page navigated. Nothing was changed." } };
  }
  type Registry = { state: string; href: string; elements: Element[]; changes: number; observer: MutationObserver };
  const scope = globalThis as unknown as { __zeusIndex?: Registry };
  const clean = (text: string | null | undefined) => (text ?? "").replace(/\s+/g, " ").trim();
  const clip = (text: string, length: number) => (text.length > length ? text.slice(0, length - 1) + "…" : text);
  const selector = [
    "a[href]", "button", "input:not([type=hidden])", "select", "textarea", "summary",
    "[role=button]", "[role=link]", "[role=checkbox]", "[role=radio]", "[role=switch]", "[role=tab]",
    "[role=menuitem]", "[role=option]", "[role=combobox]", "[role=textbox]", "[role=searchbox]",
    "[contenteditable=''], [contenteditable=true], [contenteditable=plaintext-only]",
  ].join(", ");

  const shown = (el: Element) => {
    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;
    if ((el as HTMLButtonElement).disabled || el.closest("[aria-hidden=true], [inert]")) return false;
    const style = getComputedStyle(el);
    return style.visibility !== "hidden" && style.display !== "none";
  };
  const onScreen = (el: Element) => {
    const rect = el.getBoundingClientRect();
    return rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
  };
  const roleOf = (el: Element): string => {
    const explicit = el.getAttribute("role");
    if (explicit) return explicit.split(/\s+/)[0];
    switch (el.tagName) {
      case "A": return "link";
      case "BUTTON": case "SUMMARY": return "button";
      case "SELECT": return "select";
      case "TEXTAREA": return "textbox";
      case "INPUT": {
        const type = (el as HTMLInputElement).type;
        if (["button", "submit", "reset", "image"].includes(type)) return "button";
        if (["checkbox", "radio", "range", "file", "color", "date", "time", "password"].includes(type)) return type;
        return type === "search" ? "searchbox" : "textbox";
      }
    }
    return (el as HTMLElement).isContentEditable ? "textbox" : "generic";
  };
  const isField = (el: Element) => ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);
  const labelOf = (el: Element): string => {
    const input = el as HTMLInputElement;
    const labelledBy = (el.getAttribute("aria-labelledby") ?? "")
      .split(/\s+/).filter(Boolean).map((id) => document.getElementById(id)?.textContent ?? "").join(" ");
    const forLabel = el.id ? document.querySelector(`label[for="${CSS.escape(el.id)}"]`)?.textContent : "";
    const candidates = [
      el.getAttribute("aria-label"),
      labelledBy,
      isField(el) ? "" : (el as HTMLElement).innerText,
      isField(el) ? forLabel : "",
      isField(el) ? el.closest("label")?.textContent : "",
      el.getAttribute("placeholder"),
      el.tagName === "INPUT" && ["button", "submit", "reset"].includes(input.type) ? input.value : "",
      el.getAttribute("title"),
      el.querySelector("img[alt]")?.getAttribute("alt"),
      isField(el) ? el.getAttribute("name") : "",
    ];
    for (const candidate of candidates) {
      const label = clean(candidate);
      if (label) return clip(label, 80);
    }
    return "";
  };
  const hrefOf = (el: Element): string | undefined => {
    if (el.tagName !== "A") return undefined;
    try {
      const url = new URL((el as HTMLAnchorElement).href);
      if (!/^https?:$/.test(url.protocol)) return undefined;
      const short = url.origin === location.origin ? url.pathname + url.search : url.host + url.pathname;
      return clip(short, 60);
    } catch {
      return undefined;
    }
  };

  const all = Array.from(document.querySelectorAll(selector)).filter(shown);
  const visible = all.filter(onScreen);
  const rest = all.filter((el) => !visible.includes(el));
  const picked = [...visible, ...rest].slice(0, Math.max(1, Math.min(max, 150)));

  // Same document, no DOM changes and the same elements: keep the state, so numbers hold.
  const previous = scope.__zeusIndex;
  const unchanged = !!previous && previous.href === location.href && previous.changes === 0 &&
    previous.elements.length === picked.length && previous.elements.every((el, i) => el === picked[i]);
  if (!unchanged) {
    previous?.observer.disconnect();
    const registry: Registry = {
      state: Math.random().toString(36).slice(2, 8),
      href: location.href,
      elements: picked,
      changes: 0,
      observer: new MutationObserver((records) => {
        for (const record of records) {
          for (const node of Array.from(record.addedNodes)) if (node.nodeType === Node.ELEMENT_NODE) registry.changes++;
          for (const node of Array.from(record.removedNodes)) if (node.nodeType === Node.ELEMENT_NODE) registry.changes++;
        }
      }),
    };
    registry.observer.observe(document.documentElement, { childList: true, subtree: true });
    scope.__zeusIndex = registry;
  }

  const state = scope.__zeusIndex!.state;
  const elements = picked.map((el, i): IndexedElement => {
    const item: IndexedElement = { index: i + 1, role: roleOf(el), text: labelOf(el), inViewport: onScreen(el) };
    const href = hrefOf(el);
    if (href) item.href = href;
    if (el instanceof HTMLSelectElement) {
      item.options = Array.from(el.options).slice(0, 10).map((option) => clip(clean(option.text), 40)).filter(Boolean);
    }
    return item;
  });
  return { state, total: all.length, elements };
}

/** Clicks, types into, chooses an option in, or scrolls to element `index` of page state `state`. */
export function actOnElement(
  action: "click" | "type" | "select" | "scroll",
  index: number,
  state: string,
  args: { text?: string; submit?: boolean; option?: string },
  expectedURL?: string,
):
  | { clicked: string }
  | { typed: string; submitted: boolean }
  | { selected: string }
  | { scrolled: string }
  | Failure
  | StaleFailure {
  if (expectedURL && location.href !== expectedURL) {
    return { error: { code: "stale_target", message: "The approved page navigated. Nothing was changed." } };
  }
  type Registry = { state: string; href: string; elements: Element[]; changes: number };
  const registry = (globalThis as unknown as { __zeusIndex?: Registry }).__zeusIndex;
  const clean = (value: string | null | undefined) => (value ?? "").replace(/\s+/g, " ").trim();
  const stale = (why: string): StaleFailure => ({
    error: { code: "stale_elements", message: `Element ${index} is from an older view of this page (${why}).` },
  });

  // More added or removed elements than this since the list was made counts as a new page.
  const MAJOR_CHANGE = 500;
  if (!registry) return stale("no element list for this page");
  if (state && state !== registry.state) return stale("the page state changed");
  if (registry.href !== location.href) return stale("the page navigated");
  if (registry.changes > MAJOR_CHANGE) return stale("the page changed a lot");
  const el = registry.elements[index - 1];
  if (!el) return { error: { code: "not_found", message: `There's no element ${index} on this page.` } };
  if (!el.isConnected) return stale("that element is gone");

  const html = el as HTMLElement;
  const label = clean(el.getAttribute("aria-label") || html.innerText || el.getAttribute("placeholder") || el.getAttribute("title")) ||
    el.tagName.toLowerCase();
  html.scrollIntoView({ block: "center" });

  switch (action) {
    case "scroll":
      return { scrolled: label };

    case "click":
      if ((el as HTMLButtonElement).disabled || el.getAttribute("aria-disabled") === "true") {
        return { error: { code: "disabled", message: `"${label}" can't be clicked right now.` } };
      }
      if (typeof html.click === "function") html.click();
      else el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
      return { clicked: label };

    case "select": {
      if (!(el instanceof HTMLSelectElement)) {
        return { error: { code: "not_select", message: `Element ${index} isn't a dropdown. Click it, then pick from the list.` } };
      }
      const wanted = clean(args.option).toLowerCase();
      const options = Array.from(el.options).filter((option) => !option.disabled);
      const match = options.find((option) => clean(option.text).toLowerCase() === wanted) ??
        options.find((option) => option.value.toLowerCase() === wanted) ??
        options.find((option) => clean(option.text).toLowerCase().includes(wanted));
      if (!wanted || !match) return { error: { code: "not_found", message: `"${args.option ?? ""}" isn't one of the choices.` } };
      el.focus();
      if (el.multiple) match.selected = true;
      else el.value = match.value;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
      return { selected: clean(match.text) };
    }

    case "type": {
      const input = el as HTMLInputElement;
      const textual = el instanceof HTMLTextAreaElement || html.isContentEditable ||
        (el instanceof HTMLInputElement && !["hidden", "checkbox", "radio", "submit", "button", "reset", "image", "file", "range", "color"].includes(el.type));
      if (!textual || input.disabled || input.readOnly) {
        return { error: { code: "not_editable", message: `Element ${index} isn't a text field.` } };
      }
      // Passwords and card details are always left to you.
      const autocomplete = el.getAttribute("autocomplete") ?? "";
      if ((el instanceof HTMLInputElement && el.type === "password") || /cc-|password/.test(autocomplete)) {
        return { error: { code: "sensitive_field", message: "That's a password or payment field. Please type it yourself." } };
      }
      const text = args.text ?? "";
      html.focus();
      if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
        const proto = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
        Object.getOwnPropertyDescriptor(proto, "value")?.set?.call(el, text);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      } else {
        const range = document.createRange();
        range.selectNodeContents(el);
        const selection = getSelection();
        selection?.removeAllRanges();
        selection?.addRange(range);
        document.execCommand("insertText", false, text);
      }
      let submitted = false;
      if (args.submit) {
        const form = el.closest("form");
        if (form) {
          form.requestSubmit();
        } else {
          for (const type of ["keydown", "keypress", "keyup"]) {
            el.dispatchEvent(new KeyboardEvent(type, { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }));
          }
        }
        submitted = true;
      }
      return { typed: label, submitted };
    }
  }
}

/** Scrolls the page (or, on app-like pages, its biggest scrolling panel) by `pages` screens. */
export function scrollPage(direction: "up" | "down", pages: number): { atTop: boolean; atBottom: boolean } {
  const page = document.scrollingElement ?? document.documentElement;
  let target: Element = page;
  if (page.scrollHeight <= page.clientHeight + 4) {
    let biggest = 0;
    for (const el of Array.from(document.querySelectorAll("body *"))) {
      if (el.scrollHeight <= el.clientHeight + 4 || el.clientHeight < 100) continue;
      if (!/(auto|scroll|overlay)/.test(getComputedStyle(el).overflowY)) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width * rect.height > biggest) {
        biggest = rect.width * rect.height;
        target = el;
      }
    }
  }
  const height = target === page ? innerHeight : target.clientHeight;
  const sign = direction === "up" ? -1 : 1;
  target.scrollBy({ top: sign * Math.max(0.1, pages) * height * 0.85, behavior: "instant" as ScrollBehavior });
  return {
    atTop: target.scrollTop <= 0,
    atBottom: target.scrollTop + target.clientHeight >= target.scrollHeight - 2,
  };
}

/** The page's main readable text (its article or main content, else the whole page), cut to `limit`. */
export function extractText(limit: number): { url: string; title: string; text: string; length: number; truncated: boolean } {
  const textOf = (el: Element | null) => (el as HTMLElement | null)?.innerText ?? "";
  const tidy = (text: string) =>
    text.replace(/[^\S\n]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  const bodyLength = textOf(document.body).length;

  let root: Element | null = null;
  for (const selector of ["article", "main", "[role=main]", "#content", "#main"]) {
    const found = Array.from(document.querySelectorAll(selector))
      .map((el) => ({ el, length: textOf(el).length }))
      .sort((a, b) => b.length - a.length)[0];
    if (found && found.length >= Math.min(500, bodyLength * 0.3)) {
      root = found.el;
      break;
    }
  }
  if (!root) {
    // No marked-up main content: take the block holding the most paragraph text.
    const scores = new Map<Element, number>();
    for (const paragraph of Array.from(document.querySelectorAll("p"))) {
      const length = textOf(paragraph).length;
      if (length < 40) continue;
      const parent = paragraph.parentElement;
      if (parent) scores.set(parent, (scores.get(parent) ?? 0) + length);
      const grandparent = parent?.parentElement;
      if (grandparent) scores.set(grandparent, (scores.get(grandparent) ?? 0) + length / 2);
    }
    let best = 400;
    for (const [el, score] of scores) {
      if (score > best) {
        best = score;
        root = el;
      }
    }
  }

  const text = tidy(textOf(root ?? document.body));
  const max = Math.max(1, limit);
  let cut = text;
  if (text.length > max) {
    cut = text.slice(0, max - 1);
    const lastBreak = cut.search(/\s\S*$/);
    if (lastBreak >= max * 0.8) cut = cut.slice(0, lastBreak);
    cut = cut.trimEnd() + "…";
  }
  return { url: location.href, title: document.title, text: cut, length: text.length, truncated: cut !== text };
}
