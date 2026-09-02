#!/usr/bin/env node
// Persistent transport lane for atomic actions. The game action contract stays
// atomic: one session command still dispatches exactly one MCP tool call.
const readline = require('readline');
const { McpClient } = require('../mcp_lib.js');

async function main() {
  const port = Number(process.env.MCP_PORT || 9090);
  const client = new McpClient('127.0.0.1', port);
  await client.connect();
  await client.init();
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  process.stdout.write(JSON.stringify({ ready: true, transport: 'persistent', one_tool_call_per_line: true }) + '\n');
  try {
    for await (const line of rl) {
      if (!line.trim()) continue;
      let request;
      try {
        request = JSON.parse(line);
      } catch (error) {
        process.stdout.write(JSON.stringify({ ok: false, error: 'invalid JSON command' }) + '\n');
        continue;
      }
      if (request.command === 'close') break;
      if (typeof request.tool !== 'string' || request.tool.length === 0) {
        process.stdout.write(JSON.stringify({ ok: false, error: 'tool is required' }) + '\n');
        continue;
      }
      const started = Date.now();
      try {
        const result = await client.tool(request.tool, request.args || {});
        process.stdout.write(JSON.stringify({ ok: true, tool: request.tool, elapsed_ms: Date.now() - started, result }) + '\n');
      } catch (error) {
        process.stdout.write(JSON.stringify({ ok: false, tool: request.tool, elapsed_ms: Date.now() - started, error: error.message }) + '\n');
      }
    }
  } finally {
    rl.close();
    client.disconnect();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
