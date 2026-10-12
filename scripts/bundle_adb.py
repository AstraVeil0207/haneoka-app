#!/usr/bin/env python3
"""Bundle the ADB executable, runtime libraries and third-party notices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['linux', 'darwin', 'windows'], required=True)
    parser.add_argument('--arch', choices=['x64', 'arm64', 'universal'], required=True)
    parser.add_argument('--dest', type=Path, required=True)
    parser.add_argument('--cache', type=Path, default=ROOT / 'build' / 'platform-tools')
    args = parser.parse_args()
    destination = args.dest.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / 'packaging/adb-tools.json').read_text())
    if args.platform == 'linux' and args.arch == 'arm64':
        source = shutil.which('adb')
        if not source:
            raise SystemExit('Install the native arm64 adb package before packaging.')
        shutil.copy2(source, destination / 'adb')
        libraries = subprocess.check_output(['ldd', source], text=True)
        for path in re.findall(r'=> (/\S+)', libraries):
            if Path(path).name.startswith(('libc.so', 'libm.so', 'libpthread.', 'libdl.', 'librt.')):
                continue
            lib = destination / 'lib' / Path(path).name
            lib.parent.mkdir(exist_ok=True)
            shutil.copy2(path, lib)
            result = subprocess.run(['dpkg-query', '-S', str(Path(path).resolve())], capture_output=True, text=True)
            if result.returncode == 0:
                package = result.stdout.split(': ', 1)[0].split(':', 1)[0]
                copyright_file = Path('/usr/share/doc') / package / 'copyright'
                if copyright_file.exists():
                    licenses = destination / 'licenses'
                    licenses.mkdir(exist_ok=True)
                    shutil.copy2(copyright_file, licenses / f'{package}.txt')
        notices = Path('/usr/share/doc/adb/copyright')
        if not notices.exists():
            raise SystemExit('The native ADB package must include its copyright notice.')
        shutil.copy2(notices, destination / 'NOTICE.txt')
        environment = {**os.environ, 'LD_LIBRARY_PATH': str(destination / 'lib')}
        version = subprocess.check_output([str(destination / 'adb'), 'version'], env=environment, text=True)
        help_text = subprocess.check_output([str(destination / 'adb'), 'help'], env=environment, stderr=subprocess.STDOUT, text=True)
        if 'pair' not in help_text:
            raise SystemExit('This native ADB does not support wireless pairing.')
        provenance = {'source': 'distribution package', 'version': version.strip(), 'architecture': args.arch}
    else:
        spec = lock['archives'][args.platform]
        args.cache.mkdir(parents=True, exist_ok=True)
        archive = args.cache / f"platform-tools-{args.platform}-{lock['version']}.zip"
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != spec['sha256']:
            temporary = archive.with_suffix('.download')
            with urllib.request.urlopen(spec['url'], timeout=60) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != spec['sha256']:
                temporary.unlink()
                raise SystemExit('ADB archive checksum differs from packaging/adb-tools.json.')
            temporary.replace(archive)
        with zipfile.ZipFile(archive) as contents:
            for entry in contents.infolist():
                relative = Path(entry.filename).relative_to('platform-tools')
                if (relative.name not in {'adb', 'adb.exe', 'NOTICE.txt', 'source.properties'}
                        and relative.suffix not in {'.dll', '.so', '.dylib'}):
                    continue
                output = destination / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(contents.read(entry))
                output.chmod(0o755 if relative.name == 'adb' else 0o644)
        provenance = {**spec, 'version': lock['version'], 'architecture': args.arch}
    (destination / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(f'Bundled ADB: {destination}')


if __name__ == '__main__':
    main()
