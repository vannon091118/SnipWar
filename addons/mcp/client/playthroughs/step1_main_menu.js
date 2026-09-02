// playthrough_step1.js — Main Menu → World, State Query
const net = require("net");
const fs = require("fs");

const sock = net.connect(9090, "127.0.0.1");
let buf = "", seq = 0, pending = new Map();

function call(m, p) {
  return new Promise((res, rej) => {
    const id = ++seq;
    pending.set(id, { res, rej });
    sock.write(JSON.stringify({ jsonrpc: "2.0", id, method: m, params: p || {} }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error("to")); } }, 20000);
  });
}

sock.on("data", (d) => {
  buf += d.toString();
  let i;
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

function extractText(r) {
  const c = (r.content || []).filter(x => x.type === "text").map(x => x.text).join("");
  try { return JSON.parse(c); } catch { return { raw: c }; }
}

const UX = [];

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    // === MAIN MENU ===
    console.log("=== MAIN MENU ===");
    let d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    console.log("Scene:", d.scene);
    (d.controls || []).filter(x => x.text && x.text.trim()).forEach(x =>
      console.log("  [" + x.kind + "] " + JSON.stringify(x.text.trim()) + " int=" + x.interactable + " dis=" + x.disabled)
    );

    // Click NEUES SPIEL
    console.log("\n--- Click NEUES SPIEL ---");
    let r = extractText(await call("tools/call", { name: "runtime_ux_click", arguments: { description: "Neues Spiel" } }));
    console.log("Clicked:", r.clicked);
    
    await new Promise(r => setTimeout(r, 3000));

    // === WORLD ===
    d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    console.log("\n=== WORLD ===");
    console.log("Scene:", d.scene);
    (d.controls || []).filter(x => x.text && x.text.trim()).slice(0, 25).forEach(x =>
      console.log("  [" + x.kind + "] " + JSON.stringify(x.text.trim()) + " int=" + x.interactable + " dis=" + x.disabled)
    );

    // Game State
    d = extractText(await call("tools/call", { name: "game_resources_all", arguments: { faction: "a" } }));
    console.log("\nResources:", JSON.stringify(d).slice(0, 400));

    d = extractText(await call("tools/call", { name: "game_faction_query" }));
    console.log("Factions:", JSON.stringify(d).slice(0, 600));

    d = extractText(await call("tools/call", { name: "game_ship_list", arguments: { faction: "a" } }));
    console.log("Ships:", JSON.stringify(d).slice(0, 400));

    d = extractText(await call("tools/call", { name: "game_dispatch_info", arguments: { faction: "a" } }));
    console.log("Dispatch:", JSON.stringify(d).slice(0, 400));

    console.log("\n=== DONE ===");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});