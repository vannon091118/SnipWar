// playthrough_step4.js — Click planets on map, Planet-Dossier, Werkstatt
const net = require("net");
const fs = require("fs");

const sock = net.connect(9090, "127.0.0.1");
let buf = "", seq = 0, pending = new Map();

function call(m, p, to) {
  return new Promise((res, rej) => {
    const id = ++seq;
    pending.set(id, { res, rej });
    sock.write(JSON.stringify({ jsonrpc: "2.0", id, method: m, params: p || {} }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error("to")); } }, to || 20000);
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

function E(r) {
  const c = (r.content || []).filter(x => x.type === "text").map(x => x.text).join("");
  try { return JSON.parse(c); } catch { return { raw: c }; }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

const UX = [];
function note(area, msg) { UX.push({area, msg}); console.log("  UX["+area+"]: "+msg); }

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    // Click a real planet - find one in scene tree
    let r = E(await call("tools/call", { name: "runtime_get_scene_tree", arguments: { max_depth: 7 } }));
    let tree = r.tree || [];

    // Find planet bodies (not PlanetField itself)
    let planetBodies = [];
    function scan(nodes) {
      for (let n of nodes) {
        if (n.type && (n.type.includes("Area2D") || n.type.includes("Body")) && n.path) {
          let parent = n.path.split("/").slice(-2, -1)[0] || "";
          if (parent && parent !== "PlanetField" && parent !== "PlanetNetwork") {
            planetBodies.push(n);
          }
        }
        for (let c of (n.children || [])) scan([c]);
      }
    }
    scan(tree);
    console.log("Planet bodies found:", planetBodies.length);
    let uniquePlanets = [...new Set(planetBodies.map(p => p.path.split("/").slice(-2)[0]))];
    console.log("Unique planets:", uniquePlanets.slice(0, 15).join(", "));

    // Click first planet container node
    if (uniquePlanets.length > 0) {
      let pname = uniquePlanets[0];
      let planetPath = "/root/World/PlanetField/" + pname;
      console.log("\n--- Clicking planet container: " + planetPath + " ---");
      
      // First, find the clickable area under this planet
      let planetNodes = planetBodies.filter(p => p.path.includes(pname));
      if (planetNodes.length > 0) {
        let clickTarget = planetNodes[0].path;
        console.log("Clicking area: " + clickTarget);
        r = E(await call("tools/call", { name: "runtime_click", arguments: { path: clickTarget } }));
        console.log("Click:", r.clicked);
      }
      await sleep(2000);
      
      // Check what panel opened
      let d = E(await call("tools/call", { name: "runtime_ux_scan" }));
      let texts = (d.controls || []).filter(x => x.text && x.text.trim());
      console.log("\nAfter planet click (" + texts.length + " texts):");
      texts.slice(0, 30).forEach(x => {
        let label = x.text.trim().slice(0, 70);
        console.log("  [" + (x.kind||x.type) + "] " + JSON.stringify(label) + " int="+x.interactable+" dis="+x.disabled);
      });
    }

    // Now try opening PLANET panel via button
    console.log("\n=== PLANET Panel via button ===");
    r = E(await call("tools/call", { name: "runtime_ux_click", arguments: { description: "PLANET" } }));
    console.log("PLANET click:", r.clicked);
    await sleep(1500);
    
    let d = E(await call("tools/call", { name: "runtime_ux_scan" }));
    let texts = (d.controls || []).filter(x => x.text && x.text.trim());
    console.log("After PLANET (" + texts.length + " texts):");
    texts.slice(0, 35).forEach(x => {
      let label = x.text.trim().slice(0, 70);
      console.log("  [" + (x.kind||x.type) + "] " + JSON.stringify(label) + " int="+x.interactable+" dis="+x.disabled);
    });

    // Check game state
    d = E(await call("tools/call", { name: "game_research_status", arguments: { faction: "a" } }));
    console.log("\nResearch:", JSON.stringify(d).slice(0, 400));

    d = E(await call("tools/call", { name: "game_resources_all", arguments: { faction: "a" } }));
    console.log("Resources:", JSON.stringify(d).slice(0, 300));

    fs.writeFileSync("_ux_report_2.json", JSON.stringify(UX, null, 2));
    console.log("\n=== DONE - " + UX.length + " UX notes ===");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});