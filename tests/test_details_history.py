import json
import struct
import tempfile
import time
import unittest
import zlib
from pathlib import Path
from support import Monitor, fixture, put


def seed_history(directory, now):
    history=Path(directory)/'history'; history.mkdir(exist_ok=True)
    day=now//86400000
    h=bytearray(32);struct.pack_into('<4sHHQI',h,0,b'DSCP',1,128,day,(1<<25)-1);struct.pack_into('<I',h,28,zlib.crc32(h[:28]))
    data=bytearray(h)
    for delta in (240000,180000,60000):
        r=bytearray(128);struct.pack_into('<QI',r,0,now-delta,(1<<25)-1);struct.pack_into('<i',r,12,100);struct.pack_into('<I',r,120,60);struct.pack_into('<I',r,124,zlib.crc32(r[:124]));data.extend(r)
    (history/f'{day}.dscp').write_bytes(data)
    event=bytearray(32);event[:4]=b'DSE1';event[4]=1;struct.pack_into('<QQ',event,8,now-120000,now-60000);struct.pack_into('<I',event,28,zlib.crc32(event[:28]));(history/'events.v1').write_bytes(event)


class DetailHistoryTests(unittest.TestCase):
    def test_battery_capacities_health_and_missing_cycle(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f)
            base='sys/class/power_supply/BAT1/'
            for key,value in {'energy_full':49000000,'energy_full_design':50000000,'voltage_now':7800000}.items():put(f,base+key,value)
            with Monitor(d,f) as m:
                b=m.request('get_device_info')['data']['battery']
                self.assertEqual(b['capacity_unit'],'mWh');self.assertEqual(b['full_capacity'],49000);self.assertEqual(b['health_pct_x10'],980);self.assertEqual(b['voltage_mv'],7800);self.assertIsNone(b['cycle_count'])
                put(f,base+'cycle_count',0)
                self.assertEqual(m.request('get_device_info')['data']['battery']['cycle_count'],0)
                Path(f,base+'present').unlink()
                self.assertIsNone(m.request('get_device_info')['data']['battery']['present'])
                # Detailed snapshots must not broaden the exported environment summary.
                exported=m.request('export_summary')['data'];self.assertNotIn('battery',exported);self.assertNotIn('storage',exported)

    def test_system_fixture_isolation_and_units(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f)
            put(f,'proc/deckscope_boot_ms',300000);put(f,'proc/deckscope_awake_ms',120000);put(f,'proc/loadavg','1.25 2.50 3.75 3/400 12345')
            put(f,'sys/block/zram0/mm_stat','1000000 300000 350000 0 0 0')
            put(f,'sys/module/zswap/parameters/enabled','Y')
            with Monitor(d,f) as m:
                s=m.request('get_device_info')['data']['system']
                self.assertEqual(s['suspended_ms'],180000);self.assertEqual(s['load_x1000'],[1250,2500,3750]);self.assertEqual(s['memory']['available_kib'],8192000);self.assertEqual(s['zram']['memory_used_bytes'],350000);self.assertTrue(s['zswap_enabled'])
                Path(f,'proc/deckscope_boot_ms').unlink()
                self.assertIsNone(m.request('get_device_info')['data']['system']['boot_elapsed_ms'])
                Path(f,'sys/block/zram1').mkdir()
                self.assertIsNone(m.request('get_device_info')['data']['system']['zram']['original_bytes'])

    def test_mounts_are_deduplicated_redacted_and_capacity_readable(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f)
            Path(f,'home').mkdir();Path(f,'run/media/SECRET LABEL').mkdir(parents=True)
            put(f,'proc/self/mountinfo','1 0 8:1 / / rw - ext4 /dev/SECRET rw\n2 1 8:1 / /home rw - ext4 /dev/SECRET rw\n3 1 179:1 / /run/media/SECRET\\040LABEL rw - ext4 /dev/SECRET2 rw\n4 1 0:1 / /run/media/NETWORK rw - nfs server:SECRET rw\n')
            with Monitor(d,f) as m:
                s=m.request('get_device_info')['data']['storage'];self.assertEqual(len(s['filesystems']),2);self.assertEqual(s['filesystems'][0]['kind'],'home');self.assertGreater(s['filesystems'][0]['total_bytes'],0);self.assertTrue(s['removable_present']);self.assertNotIn('SECRET',json.dumps(s));self.assertNotIn('NETWORK',json.dumps(s))

    def test_coverage_and_events_survive_restore_without_guessing_gaps(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f);now=int(time.time()*1000);seed_history(d,now)
            with Monitor(d,f) as m:
                h=m.request('query_history',{'from':now-600000,'to':now,'metric':'cpu_pct_x10','max_points':1})['data']
                self.assertEqual(len(h['samples']),1)
                self.assertEqual(h['coverage']['source_records'],3);self.assertEqual(h['coverage']['estimated_covered_ms'],180000);self.assertEqual(h['coverage']['uncovered_ms'],420000)
                self.assertEqual(len(h['coverage']['gaps']),2);self.assertEqual(h['events'][0]['kind'],'suspend_resume');self.assertTrue(h['events'][0]['estimated'])
                r=m.request('get_status')['data']['recording'];self.assertEqual(r['last_persisted_sample_ms'],now-60000);self.assertIsNone(r['last_sync_ms'])
                m.request('set_config',{'interval_ms':500});time.sleep(.65);m.request('flush')
                self.assertIsNotNone(m.request('get_status')['data']['recording']['last_sync_ms'])

    def test_bad_event_log_does_not_break_samples_or_old_archive(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f);now=int(time.time()*1000);seed_history(d,now);Path(d,'history/events.v1').write_bytes(b'BAD!'*8)
            with Monitor(d,f) as m:
                s=m.request('get_status')['data'];self.assertTrue(s['recording']['events_persistence_failed']);self.assertFalse(s['persistence_failed']);self.assertEqual(s['lo_len'],3)

    def test_missing_details_remain_explicitly_unavailable(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as f:
            fixture(f,battery=None)
            with Monitor(d,f) as m:
                info=m.request('get_device_info')['data'];self.assertFalse(info['battery']['present']);self.assertIsNone(info['battery']['voltage_mv']);self.assertEqual(info['storage']['filesystems'],[]);self.assertIsNone(info['system']['boot_elapsed_ms']);self.assertIsNone(info['system']['zram']['original_bytes'])
                put(f,'sys/block/mmcblk0/removable',0);put(f,'sys/block/mmcblk0/device/type','SD')
                storage=m.request('get_device_info')['data']['storage']
                self.assertTrue(storage['removable_present']);self.assertEqual(storage['filesystems'],[])
