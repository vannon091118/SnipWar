const net = require("net");
const fs = require("fs");

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

function printInteractables(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    const interactables = controls.filter(c => c.interactable);
    log(`  Interactables (${interactables.length}):`);
    for (const c of interactables) {
        const disabled = c.disabled ? ' [D]' : '';
        log(`    "${c.text ? c.text.trim() : '(no text)'}"${disabled}`);
    }
}

async function main() {
    const client = new McpClient(HOST, PORT);
    await client.connect();
    await client.init();
    log("MCP connected.");

    // Close the tech tree
    log("=== Closing tech tree (SCHLIESSEN) ===");
    let clicked = await client.tool("runtime_ux_click", { description: "SCHLIESSEN" });
    log(`SCHLIESSEN clicked: ${clicked.clicked}`);
    await sleep(1000);

    // Verify research status via game_research_status
    const research = await client.tool("game_research_status");
    log(`Research status: ${JSON.stringify(research).slice(0, 500)}`);

    // Check shipbuilding status
    const ships = await client.tool("game_ship_list");
    log(`Ship list: ${JSON.stringify(ships).slice(0, 500)}`);

    // Now open WERKSTATT (Workshop)
    log("=== Opening WERKSTATT ===");
    clicked = await client.tool("runtime_ux_click", { description: "WERKSTATT" });
    log(`WERKSTATT clicked: ${clicked.clicked}`);
    await sleep(2000);

    // Analyze the workshop UI
    const analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
    log(`Scene: ${analysis.scene}`);
    printInteractables(analysis);

    // Also check if we can use runtime_eval to query GameState for available ship blueprints
    const evalResult = await client.tool("runtime_eval", { code: "var state = get_node(\"/root/GameState\"); return state.has_technology(\"a\", \"shipyard_construction\") if state else false;" });
    log(`Has shipyard_construction tech: ${JSON.stringify(evalResult)}`);

    fs.writeFileSync("_mcp_werkstatt_view.json", JSON.stringify(analysis, null, 2));
    log("=== Done ===");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
