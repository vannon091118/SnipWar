// chain_camera_pan.js — Kamerasteuerung per Drag zum Finden von Planeten
// Usage: node chain_camera_pan.js [direction]  (direction: tr-bl | tl-br | center)

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

async function getCameraPos() {
  let r = E(await call("tools/call", { name: "runtime_inspect_node", arguments: { path: "/root/World/MapCamera" } }));
  for (let p of (r.properties || [])) if (p.name === "position") return p.value;
  return { x: 0, y: 0 };
}

async function dragToPan(fromX, fromY, toX, toY, repeats = 1) {
  for (let i = 0; i < repeats; i++) {
    await call("tools/call", { name: "runtime_drag", arguments: { from_x: fromX, from_y: fromY, to_x: toX, to_y: toY, duration_ms: 800 } });
    await sleep(1000);
    let cp = await getCameraPos();
    console.log("  Cam: (" + Math.round(cp.x) + ", " + Math.round(cp.y) + ")");
  }
}

sock.on("connect", async () => {
  try {
    await call("initialize", { protocolVersion: "2024-11-05" });
    await call("initialized", {});

    let cp = await getCameraPos();
    console.log("Start cam: (" + Math.round(cp.x) + ", " + Math.round(cp.y) + ")");

    // Pan right → left (moves camera right-down in world)
    console.log("\nPanning toward 0,0 (TR→BL)...");
    await dragToPan(850, 80, 100, 450, 3);

    // Pan up → down (alternative)
    console.log("\nPanning up→down...");
    await dragToPan(480, 50, 480, 400, 2);

    cp = await getCameraPos();
    console.log("\nFinal cam: (" + Math.round(cp.x) + ", " + Math.round(cp.y) + ")");

    // Screenshot
    let r = E(await call("tools/call", { name: "runtime_screenshot" }));
    console.log("Screenshot:", r.context_id);

    // Scan for planets
    let d = E(await call("tools/call", { name: "runtime_ux_scan" }));
    let texts = (d.controls || []).filter(x => x.text && x.text.trim());
    let planets = texts.filter(x => x.text.includes(":")); // "Name: Zahl" pattern
    if (planets.length > 0) {
      console.log("\nPlanets visible in panel:", planets.length);
    }

    console.log("\nDone.");
  } catch (e) { console.error("ERR:", e.message); }
  sock.destroy();
  process.exit(0);
});