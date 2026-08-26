#!/usr/bin/env node
// One observation action: read one visible UI snapshot.
const { runSingle } = require('./atomic_client.js');
runSingle('runtime_ux_scan', {}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
