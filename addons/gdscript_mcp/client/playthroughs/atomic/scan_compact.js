#!/usr/bin/env node
// Read-only convenience view over runtime_ux_scan: prints the scene plus one
// line per interactable (label / name / type / center). Compact output keeps
// the agent transcript small; the full scan stays authoritative on the wire.
const { McpClient } = require('../mcp_lib.js');

async function main() {
	const port = Number(process.env.MCP_PORT || 9090);
	const client = new McpClient('127.0.0.1', port);
	try {
		await client.connect();
		await client.init();
		const scan = await client.tool('runtime_ux_scan', {});
		console.log('scene=' + scan.scene + ' count=' + scan.count);
		for (const el of scan.interactables || []) {
			const rect = el.rect || {};
			const cx = Math.round((rect.x || 0) + (rect.w || rect.width || 0) * 0.5);
			const cy = Math.round((rect.y || 0) + (rect.h || rect.height || 0) * 0.5);
			console.log('  [' + (el.type || '?') + '] "' + (el.label || el.text || '') + '" node="' + (el.name || el.path || '') + '" center=(' + cx + ',' + cy + ')');
		}
	} finally {
		client.disconnect();
	}
}

main().catch((e) => {
	console.error('scan error: ' + e.message);
	process.exit(1);
});
