// The toolbar popup: shows whether the ZEUS Mac app's bridge is reachable.

type Status = { connected: boolean; detail?: string };

const $ = (id: string) => document.getElementById(id)!;

function render(status: Status): void {
  $("status").classList.toggle("ok", status.connected);
  $("headline").textContent = status.connected ? "Connected to ZEUS" : "ZEUS isn't connected";
  $("detail").textContent = status.connected
    ? status.detail ?? ""
    : status.detail ?? "Open ZEUS on your Mac and click Connect Chrome in the ⚡ panel.";
}

async function refresh(type: "status" | "reconnect"): Promise<void> {
  try {
    render(await chrome.runtime.sendMessage({ type }));
  } catch (error) {
    render({ connected: false, detail: String(error) });
  }
}

$("version").textContent = `v${chrome.runtime.getManifest().version}`;
$("reconnect").addEventListener("click", () => {
  $("headline").textContent = "Reconnecting…";
  void refresh("reconnect");
});
void refresh("status");
