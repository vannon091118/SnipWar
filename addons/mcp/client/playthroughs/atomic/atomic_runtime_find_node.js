#!/usr/bin/env node
// One observation action: inspect one live node position.
const { runSingle, parseArgs } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_find_node', {
  path: String(args.path || ''),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
