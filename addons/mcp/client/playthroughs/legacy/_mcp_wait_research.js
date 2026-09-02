const net = require("net");

const HOST = "127.0.0.1";
const PORT = 9090;

class McpClient {
    constructor(host, port) { this.host = host; this.port = port; this.buf = ""; this.seq = 0; this.pending = new Map(); this.sock = null; }
    connect() { return new Promise((resolve, reject) => {
        this.sock = net.connect(this.port, this.host);
        this.sock.on("connect", () => { this.sock.on("data", (d) => this._onData(d)); this.sock.on("error", reject); resolve(); });
        this.sock.on("error", reject);
        setTimeout(() => reject(new Error("timeout")), 5000);
    }); }
    _onData(d) {
        this.buf += d.toString("utf8");
        let idx; while ((idx = this.buf.indexOf("\n")) >= 0) {
            const line = this.buf.slice(0, idx).trim(); this.buf = this.buf.slice(idx + 1);
            if (!line) continue; let msg; try { msg = JSON.parse(line); } catch { continue; }
            if (msg.id && this.pending.has(msg.id)) {
                const p = this.pending.get(msg.id); this.pending.delete(msg.id);
                if (msg.error) p.reject(new Error(JSON.stringify(msg.error))); else p.resolve(msg);
            }
        }
    }
    _call(method, params) { return new Promise((resolve, reject) => {
        const id = ++this.seq; this.pending.set(id, { resolve, reject });
        this.sock.write(JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} }) + "\n");
        setTimeout(() => { if (this.pending.has(id)) { this.pending.delete(id); reject(new Error("timeout: " + method)); } }, 30000);
    }); }
    async init() { await this._call("initialize", { protocolVersion: "2024-11-05" }); await this._call("initialized", {}); }
    async tool(name, args = {}) {
        const resp = await this._call("tools/call", { name, arguments: args });
        const result = resp.result || {}; if (result.isError) return { error: true, content: result.content };
        const content = result.content || []; let merged = {};
        for (const c of content) { if (c.type === "text") { try { merged = JSON.parse(c.text); } catch { merged = { raw: c.text }; } } }
        return merged;
    }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function log(msg) { console.log("[" + new Date().toISOString().slice(11, 19) + "] " + msg); }

function printTexts(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    const texts = controls.filter(c => c.text && c.text.trim());
    log(`  All texts (${texts.length}):`);
    for (const c of texts) {
        const disabled = c.disabled ? ' [D]' : '';
        const interactable = c.interactable ? ' [I]' : '';
        log(`    "${c.text.trim()}" [${c.kind||c.type||'?'}]${disabled}${interactable} path=${c.path.split('/').pop()}`);
    }
}

async function main() {
    const client = new McpClient(HOST, PORT);
    await client.connect();
    await client.init();
    log("MCP connected.");

    // Close current panel
    log("=== Closing current panel ===");
    await client.tool("runtime_ux_click", { description: "SCHLIESSEN" });
    await sleep(500);

    // Open tech tree to check research status
    log("=== Opening FORSCHUNG (tech tree) ===");
    await client.tool("runtime_ux_click", { description: "FORSCHUNG" });
    await sleep(1500);

    let analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
    log(`Scene: ${analysis.scene}`);
    printTexts(analysis);

    // Check if "IN FORSCHUNG" still visible or if it changed
    let found = await client.tool("runtime_ux_find", { description: "IN FORSCHUNG" });
    log(`\n"IN FORSCHUNG" found: ${found.found}`);

    found = await client.tool("runtime_ux_find", { description: "Orbitales Werft" });
    if (found.found) {
        log(`Orbitales Werft-Design: disabled=${found.disabled}, interactable=${found.interactable}`);
    }

    // Check research status
    let research = await client.tool("game_research_status");
    log(`Research: ${JSON.stringify(research)}`);

    // Wait for research to complete (poll)
    log("\n=== Polling for research completion ===");
    for (let i = 0; i < 30; i++) {
        await sleep(1000);
        research = await client.tool("game_research_status");
        const completed = research.research?.completed || [];
        const active = research.research?.active || [];
        log(`  Poll ${i+1}: active=${JSON.stringify(active)}, completed=${JSON.stringify(completed)}`);
        if (completed.length > 0 || (active.length === 0 && completed.length > 0)) {
            log("  Research completed!");
            break;
        }
    }

    // Close tech tree
    log("\n=== Closing tech tree ===");
    await client.tool("runtime_ux_click", { description: "SCHLIESSEN" });
    await sleep(500);

    // Open WERKSTATT
    log("=== Opening WERKSTATT ===");
    await client.tool("runtime_ux_click", { description: "WERKSTATT" });
    await sleep(2000);

    analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
    log(`Scene: ${analysis.scene}`);
    printTexts(analysis);

    // Check if shipyard is now available
    found = await client.tool("runtime_ux_find", { description: "Werft" });
    if (found.found && !found.disabled) {
        log(`  Werft found and enabled! center: ${JSON.stringify(found.center)}`);
    }

    found = await client.tool("runtime_ux_find", { description: "SHOP" });
    log(`  SHOP found: ${found.found}`);

    log("\n=== Done ===");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
