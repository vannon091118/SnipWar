// playthrough_step3.js — PLANET tab, Werkstatt, Planet-Dossier exploration
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

function E(r) {
  const c = (r.content || []).filter(x => x.type === "text").map(x => x.text).join("");
  try { return JSON.parse(c); } catch { return { raw: c }; }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    // Close dossier by clicking SCHLIESSEN (try both CloseButton and text match)
    console.log("=== Closing current dossier ===");
    let r = E(await call("tools/call", { name: "runtime_ux_find", arguments: { description: "SCHLIESSEN" } }));
    console.log("CloseButton found:", r.found, "center:", JSON.stringify(r.center), "score:", r.match_score);
    
    if (r.found && r.path) {
      let click = E(await call("tools/call", { name: "runtime_click", arguments: { path: r.path, inject_mode: "parse" } }));
      console.log("Close click:", click.clicked);
    }
    await sleep(800);

    let d = E(await call("tools/call", { name: "runtime_ux_scan" }));
    let hasForschung = (d.controls || []).some(x => x.text && x.text.includes("FORSCHUNGSBAUM"));
    console.log("Still has FORSCHUNGSBAUM?", hasForschung);
    
    if (hasForschung) {
      // Try clicking the ◂ button (back arrow)
      let backBtn = (d.controls || []).find(x => x.text && x.text.trim() === "◂");
      if (backBtn) {
        console.log("Trying ◂ back button...");
        await call("tools/call", { name: "runtime_ux_click", arguments: { description: "◂" } });
        await sleep(800);
        d = E(await call("tools/call", { name: "runtime_ux_scan" }));
        hasForschung = (d.controls || []).some(x => x.text && x.text.includes("FORSCHUNGSBAUM"));
        console.log("After ◂ - still has FORSCHUNGSBAUM?", hasForschung);
      }
    }

    // Get scene tree to find planets
    console.log("\n=== Scene Tree (depth 6) ===");
    r = E(await call("tools/call", { name: "runtime_get_scene_tree", arguments: { max_depth: 6 } }));
    // Find PlanetField children
    let tree = r.tree || [];
    function findNode(n, name) {
      if (n.name === name) return n;
      for (let c of (n.children || [])) { let f = findNode(c, name); if (f) return f; }
      return null;
    }
    function findPath(nodes, path) {
      for (let n of nodes) { let f = findNode(n, path); if (f) return f; }
      return null;
    }
    
    let world = findPath(tree, "World");
    if (world) {
      let pf = findPath(world.children || [], "PlanetField");
      if (pf) {
        console.log("PlanetField children (" + (pf.children || []).length + "):");
        (pf.children || []).slice(0, 20).forEach(c => {
          console.log("  " + c.name + " [" + c.type + "] children=" + (c.children || []).length);
        });
      }
    }

    // Try clicking on a PlanetArea2D node  
    let planetAreas = [];
    function collectPlanets(nodes) {
      for (let n of nodes) {
        if (n.type === "PlanetArea2D" || n.name.startsWith("Planet")) planetAreas.push(n);
        for (let c of (n.children || [])) collectPlanets([c]);
      }
    }
    collectPlanets(tree);
    console.log("\nPlanet nodes found:", planetAreas.length);
    planetAreas.slice(0, 5).forEach(p => console.log("  " + p.name + " path=" + p.path));

    // Try clicking a planet by path
    if (planetAreas.length > 0) {
      let firstPlanet = planetAreas[0];
      console.log("\n--- Clicking planet: " + firstPlanet.path + " ---");
      r = E(await call("tools/call", { name: "runtime_click", arguments: { path: firstPlanet.path } }));
      console.log("Planet click:", JSON.stringify(r).slice(0, 200));
      await sleep(1500);
      
      d = E(await call("tools/call", { name: "runtime_ux_scan" }));
      let texts = (d.controls || []).filter(x => x.text && x.text.trim());
      console.log("\nAfter planet click (" + texts.length + " texts):");
      texts.slice(0, 25).forEach(x => console.log("  " + JSON.stringify(x.text.trim().slice(0, 60))));
    }

    console.log("\n=== DONE ===");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});