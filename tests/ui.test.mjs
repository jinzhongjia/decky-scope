import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const output = new URL('../.work/ui-test-build/', import.meta.url);
fs.mkdirSync(output, { recursive: true });
execFileSync(root + 'node_modules/.bin/tsc', ['src/api.ts', 'src/i18n.ts', '--outDir', fileURLToPath(output), '--target', 'ES2020', '--module', 'commonjs', '--ignoreConfig', '--skipLibCheck', '--noCheck'], { cwd: root });

function moduleFrom(name, extra = {}) {
  const js = fs.readFileSync(new URL(name.replace('.ts', '.js'), output), 'utf8');
  const exports = {};
  const sandbox = { exports, require: () => ({ callable: () => () => {}, addEventListener: () => {}, removeEventListener: () => {} }), navigator: { language: 'zh-CN' }, ...extra };
  vm.runInNewContext(js, sandbox);
  return exports;
}

test('metrics guard rejects malformed values without rendering', () => {
  const { isSample } = moduleFrom('api.ts');
  for (const value of [null, [], {}, { ts_wall_ms: '1', available: 0 }, { ts_wall_ms: 1, available: 0, cpu_pct_x10: NaN }, { ts_wall_ms: 1, available: 0, gpu_pct: 'broken' }]) assert.equal(isSample(value), false);
  assert.equal(isSample({ ts_wall_ms: 1, available: 0 }), true);
  assert.equal(isSample({ ts_wall_ms: 1, available: 1, cpu_pct_x10: 0 }), true);
});

test('missing values are not fabricated as zero and units remain explicit', () => {
  const { formatMetric, t } = moduleFrom('i18n.ts');
  assert.equal(formatMetric('gpu_pct'), '—');
  assert.equal(formatMetric('gpu_pct', 0), '0%');
  assert.equal(formatMetric('cpu_pct_x10', 123), '12.3%');
  assert.equal(formatMetric('battery_rate_mw', -14000), '-14.0 W');
  assert.equal(formatMetric('mem_used_mb', 8192), '8192 MiB');
  assert.equal(t('overview'), '总览');
});

test('English UI selection is available', () => {
  const { t } = moduleFrom('i18n.ts', { navigator: { language: 'en-US' } });
  assert.equal(t('overview'), 'Overview');
});
