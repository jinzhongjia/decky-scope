import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const output = new URL('../.work/ui-test-build/', import.meta.url);
fs.mkdirSync(output, { recursive: true });
execFileSync(root + 'node_modules/.bin/tsc', ['src/api.ts', 'src/i18n.ts', 'src/clipboard.ts', 'src/trends.ts', '--outDir', fileURLToPath(output), '--target', 'ES2020', '--module', 'commonjs', '--ignoreConfig', '--skipLibCheck', '--noCheck'], { cwd: root });

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


test('clipboard writes through the visible owner document, never the shared navigator', async () => {
  let written;
  const { copyText } = moduleFrom('clipboard.ts', { navigator: { clipboard: { writeText: () => { throw Error('wrong window'); } } } });
  const clipboard = { writeText: async function(value) { assert.equal(this, clipboard); written = value; } };
  await copyText('redacted summary', { defaultView: { navigator: { clipboard } } });
  assert.equal(written, 'redacted summary');
});

test('clipboard missing or rejected remains a caught fallback path', async () => {
  const { copyText } = moduleFrom('clipboard.ts');
  await assert.rejects(copyText('summary', null), /clipboard_unavailable/);
  await assert.rejects(copyText('summary', { defaultView: { navigator: { clipboard: { writeText: async () => { throw Error('denied'); } } } } }), /denied/);
});


test('QAM-only entry has no fullscreen navigation or route registration', () => {
  const entry = fs.readFileSync(root+'src/index.tsx','utf8');
  assert.ok(entry.includes('qam-only'));
  assert.ok(!/routerHook|addRoute|Navigate|ROUTE/.test(entry));
  assert.ok(!fs.existsSync(root+'src/Page.tsx'));
});

test('live chart memory is bounded, duplicate timestamps replace and clock reversals reset', () => {
  const {appendRecent,LIVE_LIMIT}=moduleFrom('trends.ts');
  let points=[];
  for(let i=0;i<1000;i++)points=appendRecent(points,{ts_wall_ms:i,available:0});
  assert.equal(points.length,LIVE_LIMIT);
  points=appendRecent(points,{ts_wall_ms:999,available:1,cpu_pct_x10:10});
  assert.equal(points.length,LIVE_LIMIT);assert.equal(points.at(-1).cpu_pct_x10,10);
  assert.equal(appendRecent(points,{ts_wall_ms:1,available:0}).length,1);
});

test('chart merge preserves timestamps, missing values and UTC range bounds', () => {
  const {mergeTrend}=moduleFrom('trends.ts');
  const seed={metric:'gpu_pct',resolution_ms:1000,samples:[{ts_wall_ms:10,value:5},{ts_wall_ms:20,value:null}]};
  const points=mergeTrend(seed,[{ts_wall_ms:20,gpu_pct:99},{ts_wall_ms:30},{ts_wall_ms:40,gpu_pct:0}], 'gpu_pct',15,40);
  assert.equal(JSON.stringify(points),JSON.stringify([{ts_wall_ms:20,value:null},{ts_wall_ms:30,value:null},{ts_wall_ms:40,value:0}]));
  const future={...seed,samples:[{ts_wall_ms:9000,value:5}]};
  assert.equal(mergeTrend(future,[{ts_wall_ms:30,gpu_pct:7}],'gpu_pct',0,40).length,1);
});

test('CPU/GPU share percent axes; signed power and gaps are not fabricated', () => {
  const {chartDomain,splitSegments,validateHistory}=moduleFrom('trends.ts');
  assert.equal(JSON.stringify(chartDomain([],'cpu_pct_x10')),'[0,1000]');
  assert.equal(JSON.stringify(chartDomain([],'gpu_pct')),'[0,100]');
  assert.ok(chartDomain([{value:-14000}], 'battery_rate_mw')[0]<=-14000);
  const parts=splitSegments([{ts_wall_ms:1,value:2},{ts_wall_ms:2,value:null},{ts_wall_ms:3,value:4},{ts_wall_ms:50,value:5}],10);
  assert.equal(parts.length,3);
  for(const input of [null,{}, {metric:'gpu_pct',resolution_ms:1,samples:[{value:NaN,ts_wall_ms:1}]}])assert.throws(()=>validateHistory(input,'gpu_pct'));
});


test('readable system rows opt into native gamepad focus without dummy actions', () => {
  const controls=fs.readFileSync(root+'src/Controls.tsx','utf8');
  assert.match(controls,/focusable: true/);
  const settings=fs.readFileSync(root+'src/SettingsPane.tsx','utf8');
  assert.ok(!settings.includes('Dropdown'));
});
