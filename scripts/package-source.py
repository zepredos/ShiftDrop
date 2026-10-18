#!/usr/bin/env python3
"""Create a source archive without recordings, personal files, environments, or build caches."""

from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'dist/ShiftDrop-0.2.0-source.tar.gz'
FILES = ['.gitignore', '.github', 'Package.swift', 'pyproject.toml', 'constraints.txt', 'README.md',
         'CONTRIBUTING.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE', 'docs', 'portable', 'linux', 'scripts',
         'Sources', 'Tests', 'Resources']


def include(info):
    if any(part in ('__pycache__', '.pytest_cache') for part in Path(info.name).parts) or info.name.endswith('.pyc'):
        return None
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    return info


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(OUTPUT, 'w:gz') as archive:
        for name in FILES:
            path = ROOT / name
            if path.exists(): archive.add(path, arcname='ShiftDrop-0.2.0/'+name, filter=include)
    print(OUTPUT)


if __name__ == '__main__':
    main()
