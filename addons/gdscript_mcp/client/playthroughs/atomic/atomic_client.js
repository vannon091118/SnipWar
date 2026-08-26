// Shared transport only. Atomic action scripts call runSingle exactly once.
const { McpClient } = require('../mcp_lib.js');

async function runSingle(toolName, args) {
  const port = Number(process.env.MCP_PORT || 9090);
  const client = new McpClient('127.0.0.1', port);
  try {
    await client.connect();
    await client.init();
    const result = await client.tool(toolName, args || {});
    if (result && (result.error || result._error)) {
      throw new Error(JSON.stringify(result));
    }
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } finally {
    client.disconnect();
  }
}

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    const value = argv[i + 1];
    if (value === undefined || value.startsWith('--')) result[key] = true;
    else {
      i += 1;
      result[key] = value;
    }
  }
  return result;
}

function numberArg(args, key, fallback) {
  return args[key] === undefined ? fallback : Number(args[key]);
}

module.exports = { runSingle, parseArgs, numberArg };
