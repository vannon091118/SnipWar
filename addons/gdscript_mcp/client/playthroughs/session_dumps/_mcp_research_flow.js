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

    // Open tech tree
    log("=== Opening FORSCHUNG ===");
    await client.tool("runtime_ux_click", { description: "FORSCHUNG" });
    await sleep(1500);

    // Analyze - look for FORSCHEN and IN FORSCHUNG
    let analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
    log(`Scene: ${analysis.scene}`);
    printTexts(analysis);

    // Check if "FORSCHEN" button exists
    let found = await client.tool("runtime_ux_find", { description: "FORSCHEN" });
    log(`\nFind "FORSCHEN": found=${found.found}`);
    if (found.found) {
        log(`  center: ${JSON.stringify(found.center)}`);
    }

    // Check if "IN FORSCHUNG" text exists (already researching)
    found = await client.tool("runtime_ux_find", { description: "IN FORSCHUNG" });
    log(`\nFind "IN FORSCHUNG": found=${found.found}`);

    // Click the Orbitales Werft-Design to select it
    log("\n=== Selecting Orbitales Werft-Design ===");
    found = await client.tool("runtime_ux_find", { description: "Orbitales Werft-Design" });
    if (found.found) {
        log(`  Found at: ${JSON.stringify(found.center)}`);
        const clicked = await client.tool("runtime_ux_click", { description: "Orbitales Werft-Design" });
        log(`  Clicked: ${clicked.clicked}`);
        await sleep(500);
        
        // Now look for FORSCHEN button
        analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
        log(`\nAfter selecting tech:`);
        printTexts(analysis);

        found = await client.tool("runtime_ux_find", { description: "FORSCHEN" });
        log(`\nFind "FORSCHEN" after selection: found=${found.found}`);
        if (found.found) {
            const clicked2 = await client.tool("runtime_ux_click", { description: "FORSCHEN" });
            log(`  FORSCHEN clicked: ${clicked2.clicked}`);
            await sleep(2000);
            
            analysis = await client.tool("runtime_ux_analyze", { include_visual: true });
            log(`\nAfter FORSCHEN click:`);
            printTexts(analysis);
            
            found = await client.tool("runtime_ux_find", { description: "IN FORSCHUNG" });
            log(`Find "IN FORSCHUNG": found=${found.found}`);
        }
    }

    // Check research status
    const research = await client.tool("game_research_status");
    log(`\nResearch status: ${JSON.stringify(research)}`);

    log("\n=== Done ===");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
