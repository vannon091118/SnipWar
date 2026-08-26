#!/usr/bin/env node
// One ingame action: wait once. Observation belongs to a separate script.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_wait_ms', {
  ms: numberArg(args, 'ms', 250),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
