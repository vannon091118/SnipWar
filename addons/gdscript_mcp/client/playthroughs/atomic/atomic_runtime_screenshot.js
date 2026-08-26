#!/usr/bin/env node
// One observation action: capture one visible frame.
const { runSingle, parseArgs } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_screenshot', {
  format: String(args.format || 'png'),
  persist_context: args.persistContext !== false,
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
