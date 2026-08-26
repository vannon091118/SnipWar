#!/usr/bin/env node
// One observation action: resolve one target. This script never clicks it.
const { runSingle, parseArgs } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_ux_find', {
  description: String(args.description || ''),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
