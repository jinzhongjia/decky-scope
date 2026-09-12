#!/usr/bin/env python3
"""Check local Markdown links and repository-independent developer source paths."""
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def problems(root=ROOT):
    errors = []
    docs = [root/'README.md', root/'AGENTS.md', *sorted((root/'docs').rglob('*.md'))]
    for doc in docs:
        if not doc.is_file():
            errors.append(f'Missing documentation: {doc.relative_to(root)}')
            continue
        content = doc.read_text()
        links = re.findall(r'!?\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)', content)
        links += re.findall(r'^\[[^\]]+\]:\s+(\S+)', content, re.M)
        for link in links:
            parsed = urlsplit(link.strip('<>'))
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            if parsed.path.startswith('/'):
                errors.append(f'{doc.relative_to(root)}: absolute local link {link}')
                continue
            target = (doc.parent/unquote(parsed.path)).resolve()
            if not target.is_relative_to(root.resolve()) or not target.exists():
                errors.append(f'{doc.relative_to(root)}: broken/outside link {link}')
    for base in ('scripts', 'tests', 'src', 'py_modules', 'monitor/src'):
        for p in (root/base).rglob('*'):
            if p.suffix not in ('.sh','.py','.mjs','.js','.ts','.tsx','.zig') or '__pycache__' in p.parts:
                continue
            if p.resolve() == Path(__file__).resolve():
                continue
            text = p.read_text()
            # Historical prose may name earlier projects, but executable source must not depend on them.
            if re.search(r'(?:\.\./|/home/[^/]+/[^\s]*)(?:decky-music)(?:/|[\'"\s])', text):
                errors.append(f'{p.relative_to(root)}: sibling-project path dependency')
            if '/home/jin/' in text:
                errors.append(f'{p.relative_to(root)}: developer-specific absolute path')
    return errors


if __name__ == '__main__':
    errors = problems()
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        raise SystemExit(1)
    print('Documentation links and self-contained source paths verified.')
