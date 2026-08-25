// chain_build.js — Upgrade bauen per Path (umgeht den "BAUEN"-Button-Namenskonflikt)
// Usage: node chain_build.js

const net = require("net");
const sock = net.connect(9090, "127.0.0.1");
let buf = "", seq = 0, pending = new Map();

function call(m, p) {
  return new Promise((res, rej) => {
    const id = ++seq;
    pending.set(id, { res, rej });
    sock.write(JSON.stringify({ jsonrpc: "2.0", id, method: m, params: p || {} }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error("to")); } }, 25000);
  });
}

sock.on("data", (d) => {
  buf += d.toString(); let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const l = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!l) continue;
    let m; try { m = JSON.parse(l); } catch { continue; }
    if (m.id != null && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result);
    }
  }
});

function E(r) { const c = (r.content || []).filter(x => x.type === "text").map(x => x.text).join(""); try { return JSON.parse(c); } catch { return { raw: c }; } }
const sleep = ms => new Promise(r => setTimeout(r, ms));

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    // Scan for BAUEN buttons and their parent containers
    let d = E(await call("tools/call", { name: "runtime_ux_scan" }));
    let buttons = (d.controls || []).filter(x => x.interactable && x.text && x.text.trim() === "BAUEN");
    console.log("BAUEN buttons found:", buttons.length);

    // Map each button to its parent container by extracting @PanelContainer@xxx from path
    for (let i = 0; i < buttons.length; i++) {
      let path = buttons[i].path;
      // Extract the PanelContainer ID
      let pcMatch = path.match(/@PanelContainer@(\d+)/);
      let btnNode = path.split("/").pop(); // @Button@351656
      let pcId = pcMatch ? pcMatch[1] : "?";

      // Find label in same PanelContainer
      let containerPrefix = path.substring(0, path.lastIndexOf("/@Button@"));
      let labels = (d.controls || []).filter(x =>
        x.path && x.path.startsWith(containerPrefix) &&
        x.kind === "label" && x.text && x.text.trim()
      );
      let labelText = labels.length > 0 ? labels[0].text.trim().split("\n")[0] : "(unknown)";
      console.log(i + ": " + labelText + " | path=" + btnNode + " | pc=" + pcId);
    }

    // If we have buttons, try clicking the first one that has a known label
    // Skip if we need user input about which to click
    if (buttons.length > 0) {
      console.log("\nTo click a specific BAUEN button, use:");
      console.log('  runtime_click path="' + buttons[0].path + '"');
    }

    console.log("\nDone.");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});