import argparse
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


debug = module('scope_debug_session', 'debug-session.py')
installer = module('scope_remote_installer', 'install-remote.py')


class DebugSessionTests(unittest.TestCase):
    def test_validation_rejects_shell_syntax_and_unbounded_lifetimes(self):
        self.assertEqual(debug.target('deck@example.test'), 'deck@example.test')
        for value in ('', '-oProxyCommand=x', 'deck@host;id', 'host name', 'user@$(id)'):
            with self.assertRaises(argparse.ArgumentTypeError): debug.target(value)
        for value in ('0', '59', '7201'):
            with self.assertRaises(argparse.ArgumentTypeError): debug.lifetime(value)
        with self.assertRaises(argparse.ArgumentTypeError): debug.port('80')

    def test_private_state_and_symlink_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'session.json'
            debug.save(p, {'host': 'not-a-credential'})
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)
            link = Path(folder) / 'link'; link.symlink_to(p)
            with self.assertRaises(ValueError): debug.load(link)
            with self.assertRaises(ValueError): debug.save(link, {})

    def test_start_owns_loopback_tunnel_and_bounded_unit(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(state=Path(folder)/'session.json', host='deck@example.test', port=8123, ttl=600)
            with patch.object(debug, 'ssh') as ssh, patch.object(debug, 'remote') as remote:
                debug.start(args)
                data = debug.load(args.state)
                self.assertIn('127.0.0.1:8123:127.0.0.1:8080', ssh.call_args.args)
                self.assertIn('--property=RuntimeMaxSec=600', remote.call_args.args[1])
                self.assertEqual(Path(data['directory']).stat().st_mode & 0o777, 0o700)
                with self.assertRaises(ValueError): debug.start(args)
                Path(data['directory']).rmdir()

    def test_stop_is_idempotent_and_preserves_failed_cleanup_state(self):
        with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryDirectory(prefix='deckscope-debug-') as directory:
            state = Path(folder)/'session.json'
            data = {'host':'deck@example.test','port':8123,'unit':'deckscope-debug-ab12','directory':directory,'control':directory+'/control'}
            debug.save(state,data);args=SimpleNamespace(state=state)
            with patch.object(debug,'ssh',side_effect=subprocess.CalledProcessError(255,['ssh'])):
                with self.assertRaises(subprocess.CalledProcessError):debug.stop(args)
            self.assertTrue(state.exists())
            with patch.object(debug,'ssh'), patch.object(debug,'remote',return_value=SimpleNamespace(stdout='No inhibitors')):
                debug.stop(args)
            self.assertFalse(state.exists())
            debug.stop(args)


class InstallerTests(unittest.TestCase):
    def make_tree(self, path, content):
        for name in ('main.py','plugin.json','dist/index.js','bin/deckscope-monitor'):
            p=path/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(content)

    def test_rollback_preserves_displaced_installation(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);plugins=home/'plugins';plugins.mkdir()
            self.make_tree(plugins/'DeckScope','current')
            backup=home/'deckscope-backups/DeckScope-123';self.make_tree(backup,'older')
            with patch.object(installer.subprocess,'run',return_value=SimpleNamespace(returncode=0)):
                installer.rollback(plugins,'DeckScope-123')
            self.assertEqual((plugins/'DeckScope/main.py').read_text(),'older')
            self.assertTrue(any((p/'main.py').read_text()=='current' for p in (home/'deckscope-backups').iterdir()))

    def test_failed_rollback_restores_previous_files(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);plugins=home/'plugins';plugins.mkdir()
            self.make_tree(plugins/'DeckScope','current');self.make_tree(home/'deckscope-backups/DeckScope-123','older')
            failure=subprocess.CalledProcessError(1,['systemctl'])
            with patch.object(installer.subprocess,'run',side_effect=[failure,SimpleNamespace(returncode=0)]) as run:
                with self.assertRaises(subprocess.CalledProcessError):installer.rollback(plugins,'DeckScope-123')
                self.assertEqual(run.call_count,2)
            self.assertEqual((plugins/'DeckScope/main.py').read_text(),'current')
            self.assertEqual((home/'deckscope-backups/DeckScope-123/main.py').read_text(),'older')
            with self.assertRaises(ValueError):installer.rollback(plugins,'../plugins')

    def test_install_rejects_traversal_without_touching_existing_plugin(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);plugins=home/'plugins';plugins.mkdir();self.make_tree(plugins/'DeckScope','current')
            archive=home/'bad.zip'
            with zipfile.ZipFile(archive,'w') as z:z.writestr('DeckScope/../escape','bad')
            with patch.object(installer.os,'geteuid',return_value=0),patch('sys.argv',['install',str(archive),str(plugins)]):
                with self.assertRaises(ValueError):installer.main()
            self.assertEqual((plugins/'DeckScope/main.py').read_text(),'current')
            self.assertFalse((home/'escape').exists())

    def test_install_restart_failure_restores_and_restarts_previous_version(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);plugins=home/'plugins';plugins.mkdir();self.make_tree(plugins/'DeckScope','current')
            archive=home/'good.zip'
            with zipfile.ZipFile(archive,'w') as z:
                for name in ('main.py','plugin.json','dist/index.js','bin/deckscope-monitor'):z.writestr('DeckScope/'+name,'new')
            with patch.object(installer.os,'geteuid',return_value=0),patch('sys.argv',['install',str(archive),str(plugins)]),patch.object(installer.subprocess,'run',side_effect=[subprocess.CalledProcessError(1,['systemctl']),SimpleNamespace(returncode=0)]):
                with self.assertRaises(subprocess.CalledProcessError):installer.main()
            self.assertEqual((plugins/'DeckScope/main.py').read_text(),'current')
            self.assertTrue(any(p.name.startswith('DeckScope-failed-') for p in (home/'deckscope-backups').iterdir()))


class DocumentationToolTests(unittest.TestCase):
    def test_links_and_sibling_dependencies_are_checked(self):
        checker=module('scope_doc_check','check-docs.py')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'docs').mkdir();(root/'scripts').mkdir()
            (root/'README.md').write_text('[Guide](docs/guide.md)\n')
            (root/'AGENTS.md').write_text('Rules\n');(root/'docs/guide.md').write_text('Guide\n')
            self.assertEqual(checker.problems(root),[])
            (root/'docs/guide.md').write_text('[Missing](missing.md)\n')
            (root/'scripts/bad.mjs').write_text("import '../"+'decky'+'-music'+"/external.mjs';\n")
            found=checker.problems(root)
            self.assertTrue(any('broken/outside' in message for message in found))
            self.assertTrue(any('sibling-project' in message for message in found))

    def test_shell_help_and_confirmation_guards_are_offline(self):
        for name in ('deploy.sh','rollback.sh','device-check.sh','logs.sh','discover.sh'):
            result=subprocess.run(['bash',str(ROOT/'scripts'/name),'--help'],cwd='/',text=True,capture_output=True)
            self.assertEqual(result.returncode,0,(name,result.stderr))
            self.assertIn('Usage:',result.stdout)
        result=subprocess.run(['bash',str(ROOT/'scripts/deploy.sh')],cwd='/',text=True,capture_output=True)
        self.assertEqual(result.returncode,2)
