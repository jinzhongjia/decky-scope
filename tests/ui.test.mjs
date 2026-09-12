import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const output = new URL('../.work/ui-test-build/', import.meta.url);
fs.mkdirSync(output, { recursive: true });
execFileSync(root + 'node_modules/.bin/tsc', ['src/api.ts', 'src/i18n.ts', 'src/clipboard.ts', 'src/trends.ts', 'src/Controls.tsx', 'src/SystemDetails.tsx', 'src/HistoryIntegrity.tsx', 'src/monitorMetrics.ts', 'src/MonitorPicker.tsx', 'src/MonitorPane.tsx', '--jsx', 'react-jsx', '--outDir', fileURLToPath(output), '--target', 'ES2020', '--module', 'commonjs', '--ignoreConfig', '--skipLibCheck', '--noCheck'], { cwd: root });

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


function controlsModule() {
  const jsx=(type,props)=>({type,props});
  return moduleFrom('Controls.ts',{require:(name)=>name==='react/jsx-runtime'?{jsx,jsxs:jsx}:{Field:'Field',Focusable:'Focusable',DialogButton:'DialogButton',PanelSection:'PanelSection',PanelSectionRow:'PanelSectionRow'}});
}
test('readable rows use native Field focus without dummy activation handlers', () => {
  const {Row}=controlsModule();const field=Row({label:'Kernel',value:'6.16',long:true}).props.children;
  assert.equal(field.type,'Field');assert.equal(field.props.focusable,true);
  assert.equal(field.props.childrenLayout,'below');assert.equal(field.props.onActivate,undefined);
  assert.equal(Row({label:'zero',value:0}).props.children.props.children.props.children,0);
  assert.equal(Row({label:'missing',value:null}).props.children.props.children.props.children,'—');
});
test('both action pairs belong to horizontal native focus groups', () => {
  const {Actions}=controlsModule();const node=Actions({children:['left','right']});
  assert.equal(node.type,'Focusable');assert.equal(node.props['flow-children'],'horizontal');
  const system=fs.readFileSync(root+'src/SystemPane.tsx','utf8');
  assert.equal((system.match(/<Actions>/g)||[]).length,2);
  assert.ok(!system.includes('<div className="ds-actions">'));
});
test('native styling keeps one host scroller and does not intercept touch', () => {
  const css=fs.readFileSync(root+'src/styles.ts','utf8');
  assert.ok(!css.includes('touch-action:'));
  assert.ok(!/\.gpfocus|:focus-visible|linear-gradient|overflow(?:-x|-y)?:/.test(css));
  const index=fs.readFileSync(root+'src/index.tsx','utf8');
  assert.ok(!index.includes('<footer'));
  assert.ok(!/onTouchMove|onWheel|preventDefault|scrollIntoView/.test(index));
});

test('system and settings omit the redundant root-permission tagline in both languages', () => {
  for (const name of ['SystemPane.tsx', 'SettingsPane.tsx']) {
    const source=fs.readFileSync(root+'src/'+name,'utf8');
    assert.ok(!source.includes('t("readOnly")'));
  }
  const strings=fs.readFileSync(root+'src/i18n.ts','utf8');
  assert.ok(!strings.includes('readOnly:'));
});

test('new chart groups cover recorded metrics without timer-based polling', () => {
  const source=fs.readFileSync(root+'src/monitorMetrics.ts','utf8');
  for(const key of ['mem_used_mb','swap_used_mb','cpu_temp_mc','gpu_temp_mc','nvme_temp_mc','fan_rpm','disk_read_kbps','disk_write_kbps','net_rx_kbps','net_tx_kbps','psi_cpu_some_x100','psi_mem_some_x100','psi_mem_full_x100','psi_io_some_x100','psi_io_full_x100']) assert.ok(source.includes('"'+key+'"'),key);
  assert.ok(!/setInterval|setTimeout/.test(source));
});

test('PSI percentage axes and known gaps remain distinct from utilization and interpolation', () => {
  const {chartDomain,splitSegments,validateHistory}=moduleFrom('trends.ts');
  assert.equal(JSON.stringify(chartDomain([],'psi_io_some_x100')),'[0,10000]');
  assert.equal(splitSegments([{ts_wall_ms:1,value:0},{ts_wall_ms:50,value:0}],1000,[{from_ms:2,to_ms:49}]).length,2);
  assert.throws(()=>validateHistory({metric:'gpu_pct',resolution_ms:1000,samples:[],coverage:{from_ms:0,to_ms:100,estimated_covered_ms:Infinity,uncovered_ms:0,gaps:[]}},'gpu_pct'));
});

function detailModule(name) {
  const jsx=(type,props)=>({type,props});
  const i18n=moduleFrom('i18n.ts',{navigator:{language:'en-US'}});
  return moduleFrom(name,{require:(id)=>id==='react/jsx-runtime'?{jsx,jsxs:jsx}:id==='./i18n'?i18n:{Row:'Row',Section:'Section'}});
}
function rows(node) {
  if(Array.isArray(node))return node.flatMap(rows);
  if(!node||typeof node!=='object')return [];
  return [...(node.type==='Row'?[node.props]:[]),...rows(node.props?.children)];
}
test('battery fields preserve zero cycle count and missing voltage in rendered rows', () => {
  const {SystemDetails}=detailModule('SystemDetails.ts');
  const result=rows(SystemDetails({pane:'battery',device:{battery:{present:true,status:'Full',full_capacity:50000,design_capacity:50000,capacity_unit:'mWh',health_pct_x10:1000,cycle_count:0,voltage_mv:null}}}));
  assert.equal(result.find(r=>r.label==='Cycle count').value,0);
  assert.equal(result.find(r=>r.label==='Battery voltage').value,'—');
  assert.equal(result.find(r=>r.label==='Full-charge capacity').value,'50.00 Wh');
  assert.equal(result.find(r=>r.label==='Estimated health').value,'100.0%');
});
test('integrity rows do not label unexplained gaps as suspend and support old responses', () => {
  const {HistoryIntegrity}=detailModule('HistoryIntegrity.ts');
  const result=rows(HistoryIntegrity({metricLabel:'CPU',status:null,history:{coverage:{estimated_covered_ms:1000,uncovered_ms:2000,to_ms:3000,gaps:[{from_ms:0,to_ms:2000}]},events:[]}}));
  assert.ok(result.some(r=>r.label==='No data'));
  assert.ok(!result.some(r=>r.label.startsWith('Suspend')));
  assert.doesNotThrow(()=>HistoryIntegrity({metricLabel:'CPU',status:null}));
});

test('sub-minute coverage durations do not display as zero minutes', () => {
  const {duration}=moduleFrom('i18n.ts');
  assert.equal(duration(59537),'59 s');
  assert.equal(duration(500),'<1 s');
  assert.equal(duration(0),'0 s');
  assert.equal(duration(60000),'1 min');
});

test('monitor defaults to a single CPU chart and collapsed optional details', () => {
 const source=fs.readFileSync(root+'src/MonitorPane.tsx','utf8');
 assert.ok(source.includes('useState("cpu_pct_x10")'));
 assert.ok(source.includes('const metrics = [metric]'));
 assert.ok(source.includes('const [integrityOpen, setIntegrityOpen] = useState(false)'));
 assert.ok(source.includes('const [infoOpen, setInfoOpen] = useState(false)'));
 assert.ok(!/ds-extra-charts|ds-telemetry|setInterval|setTimeout/.test(source));
});
test('all 19 metrics remain available in both locales', () => {
 for(const language of ['en-US','zh-CN']){
  const i18n=moduleFrom('i18n.ts',{navigator:{language}});
  const {monitorGroups}=moduleFrom('monitorMetrics.ts',{require:()=>i18n});
  const all=Object.values(monitorGroups()).flatMap(g=>g.items);
  assert.equal(all.length,19);assert.equal(new Set(all.map(m=>m.metric)).size,19);
  assert.ok(all.every(m=>typeof m.label==='string'&&m.label.length>0));
  assert.ok(all.find(m=>m.metric==='battery_rate_mw').note);
 }
});

test('default monitor render contains one chart and keeps diagnostics behind disclosures', () => {
  const jsx=(type,props)=>({type,props});
  const i18n=moduleFrom('i18n.ts');
  const catalog=moduleFrom('monitorMetrics.ts',{require:()=>i18n});
  const trends=moduleFrom('trends.ts');
  const {MonitorPane}=moduleFrom('MonitorPane.ts',{
    require:(id)=>{
      if(id==='react/jsx-runtime')return {jsx,jsxs:jsx,Fragment:'Fragment'};
      if(id==='react')return {useState:v=>[v,()=>{}],useEffect:()=>{},useRef:v=>({current:v}),useMemo:f=>f()};
      if(id==='./i18n')return i18n;
      if(id==='./monitorMetrics')return catalog;
      if(id==='./trends')return trends;
      if(id==='./live')return {useLive:()=>({latest:{ts_wall_ms:Date.now(),cpu_pct_x10:127,cpu_mhz:2000},status:{interval_ms:1000},recent:[],refresh:()=>{}})};
      return {DialogButton:'DialogButton',MiniChart:'MiniChart',MonitorPicker:'MonitorPicker',MonitorDisclosure:'MonitorDisclosure',HistoryIntegrity:'HistoryIntegrity'};
    }
  });
  const flatten=n=>Array.isArray(n)?n.flatMap(flatten):n&&typeof n==='object'?[n,...flatten(n.props?.children)]:[];
  const nodes=flatten(MonitorPane());
  assert.equal(nodes.filter(n=>n.type==='MiniChart').length,1);
  assert.equal(nodes.find(n=>n.type==='MonitorPicker').props.mode,null);
  assert.ok(nodes.filter(n=>n.type==='MonitorDisclosure').every(n=>n.props.open===false));
});

function pickerHarness(language) {
  const jsx=(type,props)=>({type,props});
  const hooks=[];let cursor=0;
  const i18n=moduleFrom('i18n.ts',{navigator:{language}});
  const catalog=moduleFrom('monitorMetrics.ts',{require:()=>i18n});
  const selected=[];
  const props={metric:'cpu_pct_x10',range:300000,mode:null,onMode:v=>props.mode=v,onMetric:v=>{props.metric=v;selected.push(v);},onRange:v=>props.range=v};
  const {MonitorPicker}=moduleFrom('MonitorPicker.ts',{require:id=>{
    if(id==='react/jsx-runtime')return {jsx,jsxs:jsx,Fragment:'Fragment'};
    if(id==='react')return {
      useState:v=>{const i=cursor++;if(!(i in hooks))hooks[i]=v;return [hooks[i],next=>hooks[i]=next];},
      useRef:v=>{const i=cursor++;if(!(i in hooks))hooks[i]={current:v};return hooks[i];},
      useEffect:()=>{},
    };
    if(id==='./i18n')return i18n;
    if(id==='./monitorMetrics')return catalog;
    return {DialogButton:'DialogButton',Focusable:'Focusable',FaCheck:'FaCheck',FaChevronLeft:'FaChevronLeft',FaChevronRight:'FaChevronRight',FaChevronUp:'FaChevronUp',FaChevronDown:'FaChevronDown'};
  }});
  const flat=n=>Array.isArray(n)?n.flatMap(flat):n&&typeof n==='object'?[n,...flat(n.props?.children)]:[];
  const text=n=>Array.isArray(n)?n.map(text).join(''):typeof n==='string'?n:n&&typeof n==='object'?text(n.props?.children):'';
  const render=()=>{cursor=0;return flat(MonitorPicker(props));};
  const byClass=(name)=>render().filter(n=>n.props?.className?.split(' ').includes(name));
  const click=(name,label)=>{const n=byClass(name).find(n=>label===undefined||text(n)===label);assert.ok(n,`${name}: ${label}`);n.props.onClick();};
  return {render,byClass,click,text,props,selected,t:i18n.t,flat};
}
for(const language of ['zh-CN','en-US']) {
  test(`two-level picker separates navigation from selection (${language})`,()=>{
    const h=pickerHarness(language);
    h.click('ds-metric-trigger');
    assert.equal(h.byClass('ds-category-option').length,0);
    assert.equal(h.byClass('ds-metric-option').length,4);
    assert.equal(h.byClass('ds-metric-option').filter(n=>n.props['aria-pressed']).length,1);
    assert.ok(h.render().some(n=>n.type==='h3'&&h.text(n)===h.t('groupMetricTitle').replace('{group}',h.t('performanceGroup'))));
    h.click('ds-category-back');
    assert.equal(h.byClass('ds-metric-option').length,0);
    assert.equal(h.byClass('ds-category-option').length,5);
    for(const n of h.byClass('ds-category-option')){
      assert.equal(n.props['aria-pressed'],undefined);
      assert.ok(h.flat(n).some(n=>n.type==='FaChevronRight'));
      assert.ok(!h.flat(n).some(n=>n.type==='FaCheck'));
    }
    h.click('ds-category-option',h.t('memoryGroup'));
    assert.equal(h.selected.length,0,'category navigation must not change the selected metric');
    assert.equal(h.byClass('ds-category-option').length,0);
    assert.equal(h.byClass('ds-metric-option').length,2);
    h.click('ds-metric-option',h.t('memory'));
    assert.equal(h.props.metric,'mem_used_mb');assert.equal(h.props.mode,null);
    assert.equal(h.byClass('ds-metric-option').length,0);
    h.click('ds-metric-trigger');
    assert.equal(h.byClass('ds-metric-option').length,2,'open in selected metric category');
    h.click('ds-category-back');h.click('ds-category-option',h.t('performanceGroup'));
    h.click('ds-metric-trigger');h.click('ds-metric-trigger');
    assert.equal(h.byClass('ds-metric-option').length,2,'discard uncommitted browsing category');
    assert.deepEqual(h.selected,['mem_used_mb']);
  });
}
