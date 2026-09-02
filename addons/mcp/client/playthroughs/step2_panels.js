// playthrough_step2.js — FORSCHUNG, ECONOMY, PLANET panels exploration
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

const sleep = ms => new Promise(r => setTimeout(r, ms));
const UX_NOTES = [];

function ux(area, note) { const e = { area, note }; UX_NOTES.push(e); console.log("  UX [" + area + "]: " + note); }

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    // Verify we're in world
    let d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    if (d.scene !== "game_view") {
      console.log("NOT IN GAME VIEW, scene:", d.scene); sock.destroy(); process.exit(1);
    }

    // ===== FORSCHUNG PANEL =====
    console.log("\n=== FORSCHUNG PANEL ===");
    await call("tools/call", { name: "runtime_ux_click", arguments: { description: "FORSCHUNG" } });
    await sleep(1500);

    d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    console.log("Scene after FORSCHUNG:", d.scene);

    // List all interactable items
    let items = (d.controls || []).filter(x => x.interactable && x.text && x.text.trim());
    console.log("Interactable items:");
    items.forEach(x => {
      const label = x.text.trim().split("\n")[0].slice(0, 50);
      console.log("  [" + (x.disabled ? "DISABLED" : "ACTIVE") + "] " + JSON.stringify(label) + " path=" + (x.path || "").split("/").pop());
    });

    // Find an active (non-disabled) tech to research
    let activeTechs = items.filter(x => !x.disabled && x.path && x.path.includes("TechNode"));
    if (activeTechs.length > 0) {
      let tech = activeTechs[0];
      console.log("\n--- Researching: " + tech.text.trim().split("\n")[0] + " ---");
      let r = extractText(await call("tools/call", { name: "runtime_ux_click", arguments: { description: tech.text.trim().split("\n")[0] } }));
      console.log("Click result:", r.clicked);
      await sleep(800);

      // Check if research started
      d = extractText(await call("tools/call", { name: "game_research_status", arguments: { faction: "a" } }));
      console.log("Research status:", JSON.stringify(d).slice(0, 400));

      d = extractText(await call("tools/call", { name: "game_resources_all", arguments: { faction: "a" } }));
      console.log("Resources after research:", JSON.stringify(d).slice(0, 300));
    }

    // Check if there are more active techs
    d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    items = (d.controls || []).filter(x => x.interactable && !x.disabled && x.path && x.path.includes("TechNode"));
    console.log("\nRemaining active techs:", items.length);
    items.forEach(x => console.log("  " + x.text.trim().split("\n")[0]));

    // Research another if available
    if (items.length > 0) {
      let tech2 = items[0];
      console.log("\n--- Researching 2nd: " + tech2.text.trim().split("\n")[0] + " ---");
      await call("tools/call", { name: "runtime_ux_click", arguments: { description: tech2.text.trim().split("\n")[0] } });
      await sleep(500);
      d = extractText(await call("tools/call", { name: "game_resources_all", arguments: { faction: "a" } }));
      console.log("Resources:", JSON.stringify(d).slice(0, 300));
    }

    // ===== ECONOMY PANEL =====
    console.log("\n=== ECONOMY PANEL ===");
    // Close FORSCHUNG? Can't. Click ECONOMY tab instead
    await call("tools/call", { name: "runtime_ux_click", arguments: { description: "ECONOMY" } });
    await sleep(1500);

    d = extractText(await call("tools/call", { name: "runtime_ux_scan" }));
    console.log("Scene after ECONOMY:", d.scene);
    items = (d.controls || []).filter(x => x.text && x.text.trim());
    console.log("Economy panel items (" + items.length + "):");
    items.slice(0, 25).forEach(x => {
      const label = x.text.trim().split("\n")[0].slice(0, 60);
      console.log("  [" + (x.kind || x.type) + "] " + JSON.stringify(label) + " int=" + x.interactable + " dis=" + x.disabled);
    });

    // ===== SAVE UX NOTES =====
    fs.writeFileSync("_ux_report_1.json", JSON.stringify(UX_NOTES, null, 2));
    console.log("\n=== DONE - " + UX_NOTES.length + " UX notes ===");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});