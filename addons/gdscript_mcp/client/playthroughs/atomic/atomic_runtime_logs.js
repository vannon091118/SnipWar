#!/usr/bin/env node
// One observation action: read one log delta.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_ux_logs', {
  cursor: numberArg(args, 'cursor', 0),
  limit: numberArg(args, 'limit', 80),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
