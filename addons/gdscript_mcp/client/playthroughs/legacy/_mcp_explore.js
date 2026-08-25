const net = require("net");
const fs = require("fs");
const path = require("path");

const HOST = "127.0.0.1";
const PORT = 9090;

class McpClient {
    constructor(host, port) {
        this.host = host;
        this.port = port;
        this.buf = "";
        this.seq = 0;
        this.pending = new Map();
        this.sock = null;
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
            let msg;
            try { msg = JSON.parse(line); } catch { continue; }
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
                if (this.pending.has(id)) {
                    this.pending.delete(id);
                    reject(new Error("timeout: " + method));
                }
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
            if (c.type === "text") {
                try { merged = JSON.parse(c.text); } catch { merged = { raw: c.text }; }
            }
        }
        return merged;
    }
}

(async () => {
    const client = new McpClient(HOST, PORT);
    await client.connect();
    await client.init();

    // Wait for virtual mouse to be active
    let status = await client.tool("runtime_mcp_status");
    console.log("Scene:", status.state);

    // Take a screenshot to see the game state
    const screenshot = await client.tool("runtime_screenshot", {});
    console.log("Screenshot:", JSON.stringify(screenshot, null, 2));

    // Analyze the UI
    const analysis = await client.tool("runtime_ux_analyze", {});
    console.log("UX Analysis:", JSON.stringify(analysis, null, 2));

    // Save screenshot path if available
    if (screenshot.path) {
        const imgPath = path.resolve(screenshot.path);
        if (fs.existsSync(imgPath)) {
            console.log("Screenshot saved at:", imgPath);
            console.log("Size:", fs.statSync(imgPath).size, "bytes");
        }
    }
})();
