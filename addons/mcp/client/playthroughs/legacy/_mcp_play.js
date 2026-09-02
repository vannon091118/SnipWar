const net = require("net");
const fs = require("fs");
const path = require("path");

const HOST = "127.0.0.1";
const PORT = 9090;

class McpClient {
    constructor(host, port) {
        this.host = host; this.port = port;
        this.buf = ""; this.seq = 0; this.pending = new Map(); this.sock = null;
    }
    connect() {
        return new Promise((resolve, reject) => {
            this.sock = net.connect(this.port, this.host);
            this.sock.on("connect", () => {
                this.sock.on("data", (d) => this._onData(d));
                this.sock.on("error", reject);
                resolve();
            });
            this.sock.on("error", reject);
            setTimeout(() => reject(new Error("timeout")), 5000);
        });
    }
    _onData(d) {
        this.buf += d.toString("utf8");
        let idx;
        while ((idx = this.buf.indexOf("\n")) >= 0) {
            const line = this.buf.slice(0, idx).trim();
            this.buf = this.buf.slice(idx + 1);
            if (!line) continue;
            let msg; try { msg = JSON.parse(line); } catch { continue; }
            if (msg.id && this.pending.has(msg.id)) {
                const p = this.pending.get(msg.id);
                this.pending.delete(msg.id);
                if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
                else p.resolve(msg);
            }
        }
    }
    _call(method, params) {
        return new Promise((resolve, reject) => {
            const id = ++this.seq;
            this.pending.set(id, { resolve, reject });
            this.sock.write(JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} }) + "\n");
            setTimeout(() => {
                if (this.pending.has(id)) { this.pending.delete(id); reject(new Error("timeout: " + method)); }
            }, 30000);
        });
    }
    async init() {
        await this._call("initialize", { protocolVersion: "2024-11-05" });
        await this._call("initialized", {});
    }
    async tool(name, args = {}) {
        const resp = await this._call("tools/call", { name, arguments: args });
        const result = resp.result || {};
        if (result.isError) return { error: true, content: result.content };
        const content = result.content || [];
        let merged = {};
        for (const c of content) {
            if (c.type === "text") { try { merged = JSON.parse(c.text); } catch { merged = { raw: c.text }; } }
        }
        return merged;
    }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function waitFrames(client, n) {
    for (let i = 0; i < n; i++) await client.tool("runtime_wait_frames", {});
}

function log(msg) { console.log("[" + new Date().toISOString().slice(11, 19) + "] " + msg); }

async function waitForScene(client, expectedScene, timeoutMs = 15000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const scan = await client.tool("runtime_ux_scan", {});
        const scene = scan.scene || "?";
        log(`  scene=${scene}`);
        if (scene === expectedScene) return true;
        await sleep(500);
    }
    return false;
}

function printInteractables(analysis) {
    const interactables = analysis.interactables || [];
    log(`  Interactables (${interactables.length}):`);
    for (const it of interactables) {
        log(`    - ${it.text || "(no text)"} @ center(${it.center.x},${it.center.y}) ${it.disabled ? "[DISABLED]" : ""}`);
    }
    const controls = (analysis.live || analysis).controls || [];
    if (controls.length > 0) {
        log(`  All controls (${controls.length}):`);
        for (const c of controls) {
            log(`    - ${c.text || "(empty)"} [${c.kind || c.type || "?"}] @ ${c.path}`);
        }
    }
}

function printTexts(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    log(`  Texts (${controls.length}):`);
    for (const c of controls) {
        if (c.text && c.text.trim()) {
            log(`    "${c.text}" [${c.kind || c.type || "?"}] path=${c.path}`);
        }
    }
}

async function main() {
    const client = new McpClient(HOST, PORT);
    await client.connect();
    await client.init();
    log("MCP connected.");

    // ===== Step 1: Click NEUES SPIEL =====
    log("=== Main Menu: clicking NEUES SPIEL ===");
    const analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
    log(`Scene: ${analysis.scene}`);
    printInteractables(analysis);

    const clicked = await client.tool("runtime_ux_click", { description: "Neues Spiel" });
    log(`NEUES SPIEL clicked: ${clicked.clicked}`);

    // ===== Step 2: Wait for world to load =====
    log("=== Waiting for World scene ===");
    const worldLoaded = await waitForScene(client, "game_view", 15000);
    log(`World loaded: ${worldLoaded}`);

    // ===== Step 3: Analyze world UI =====
    if (worldLoaded) {
        await sleep(2000);
        log("=== Analyzing World UI ===");
        const worldAnalysis = await client.tool("runtime_ux_analyze", { include_visual: true });
        log(`Scene: ${worldAnalysis.scene}`);
        printTexts(worldAnalysis);
        printInteractables(worldAnalysis);

        // Take screenshot
        const screenshot = await client.tool("runtime_screenshot", {});
        log(`Screenshot: ${screenshot.context_id || "none"}`);
        if (screenshot.absolute_path && fs.existsSync(screenshot.absolute_path)) {
            log(`  saved to: ${screenshot.absolute_path}`);
        }
    }

    // Save results
    fs.writeFileSync("_mcp_game_state.json", JSON.stringify({
        timestamp: new Date().toISOString(),
        step: "main_menu_to_world",
        world_loaded: worldLoaded
    }, null, 2));
    log("=== Phase 1 complete ===\n");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
