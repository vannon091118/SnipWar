#!/usr/bin/env node
// One visible player atom per process: send exactly ONE MCP tool call, print
// its raw result line. No sequencing, no decisions — the calling agent reads
// the result and decides the next atom itself (Atom-Vertrag).
// Usage: MCP_PORT=9090 node mcp_player_atom.js <tool> '<json-args>'
const { McpClient } = require('../mcp_lib.js');

const tool = process.argv[2];
let args = {};
try { args = JSON.parse(process.argv[3] || '{}'); } catch (e) {
	console.error('invalid args json: ' + e.message);
	process.exit(2);
}
if (!tool) {
	console.error('usage: node mcp_player_atom.js <tool> \'{"x":1}\'');
	process.exit(2);
}

async function main() {
	const port = Number(process.env.MCP_PORT || 9090);
	const client = new McpClient('127.0.0.1', port);
	try {
		await client.connect();
		await client.init();
		const result = await client.tool(tool, args);
		process.stdout.write(JSON.stringify(result) + '\n');
	} finally {
		client.disconnect();
	}
}

main().catch((e) => {
	console.error('atom error: ' + e.message);
	process.exit(1);
});
