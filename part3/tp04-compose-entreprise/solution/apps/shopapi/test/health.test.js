const { test } = require('node:test');
const assert = require('node:assert');
test('le module serveur se charge', () => {
  assert.ok(require('fs').existsSync(__dirname + '/../src/server.js'));
});
