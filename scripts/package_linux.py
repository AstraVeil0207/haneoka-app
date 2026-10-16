#!/usr/bin/env python3
"""Package the real Flutter Linux bundle as tar, DEB, RPM, Arch and AppImage."""
import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(*arguments, **kwargs):
    subprocess.run([str(arg) for arg in arguments], check=True, **kwargs)


def root_owner(info):
    info.uid = info.gid = 0
    info.uname = info.gname = 'root'
    return info


def compressed_tree(directory):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz', format=tarfile.PAX_FORMAT) as archive:
        for path in sorted(directory.iterdir()):
            archive.add(path, arcname=path.name, filter=root_owner)
    return data.getvalue()


def debian_member(output, name, data):
    header = f'{name + "/":<16}{int(time.time()):<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'
    output.write(header.encode('ascii'))
    output.write(data)
    if len(data) % 2:
        output.write(b'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--arch', choices=['x64', 'arm64'], required=True)
    parser.add_argument('--out', type=Path, default=ROOT / 'dist')
    parser.add_argument('--formats', default='tar,deb,arch')
    parser.add_argument('--linuxdeploy', type=Path)
    args = parser.parse_args()
    formats = set(args.formats.split(','))
    if formats - {'tar', 'deb', 'rpm', 'arch', 'appimage', 'snap'}:
        raise SystemExit('Unknown package format')
    bundle = args.bundle.resolve()
    if not (bundle / 'haneoka').is_file():
        raise SystemExit('Build the Flutter Linux release bundle first')
    if not (bundle / 'tools/adb/adb').is_file():
        raise SystemExit('Bundle ADB before creating installers')
    with (bundle / 'haneoka').open('rb') as executable:
        header = executable.read(20)
    if header[:4] != b'\x7fELF' or len(header) < 20 or header[4] != 2:
        raise SystemExit('Expected a 64-bit ELF application')
    machine = int.from_bytes(header[18:20], 'little' if header[5] == 1 else 'big')
    if machine != (62 if args.arch == 'x64' else 183):
        raise SystemExit('Linux executable architecture does not match the package architecture')
    args.out.mkdir(parents=True, exist_ok=True)
    output = args.out.resolve()
    architecture = 'x86_64' if args.arch == 'x64' else 'aarch64'
    deb_arch = 'amd64' if args.arch == 'x64' else 'arm64'
    name = f'haneoka-linux-{args.arch}'
    with tempfile.TemporaryDirectory(prefix='haneoka-package-') as temp:
        temp = Path(temp)
        stage = temp / 'root'
        app = stage / 'usr/share/haneoka'
        shutil.copytree(bundle, app, symlinks=True)
        shutil.copy2(ROOT / 'LICENSE', app / 'LICENSE')
        bindir = stage / 'usr/bin'
        bindir.mkdir(parents=True)
        launcher = bindir / 'haneoka'
        launcher.write_text('#!/bin/sh\nexec /usr/share/haneoka/haneoka "$@"\n')
        launcher.chmod(0o755)
        desktop = stage / 'usr/share/applications/org.haneoka.haneoka.desktop'
        desktop.parent.mkdir(parents=True)
        desktop.write_text('[Desktop Entry]\nType=Application\nName=Haneoka\n'
                           'Comment=Our Notes catalogue and save reader\nExec=haneoka %u\n'
                           'Icon=org.haneoka.haneoka\nCategories=Game;Utility;\n'
                           'Terminal=false\nMimeType=application/x-haneoka-save;x-scheme-handler/haneoka;\n')
        icon = stage / 'usr/share/icons/hicolor/512x512/apps/org.haneoka.haneoka.png'
        icon.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'assets/brand/android-chrome-512x512.png', icon)
        mime = stage / 'usr/share/mime/packages/org.haneoka.haneoka.xml'
        mime.parent.mkdir(parents=True)
        mime.write_text('<?xml version="1.0"?><mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">'
                        '<mime-type type="application/x-haneoka-save"><comment>Haneoka save archive</comment>'
                        '<glob pattern="*.haneoka-save"/></mime-type></mime-info>\n')
        if 'tar' in formats:
            with tarfile.open(output / f'{name}.tar.gz', 'w:gz') as archive:
                for path in bundle.iterdir():
                    archive.add(path, arcname=path.name)
                archive.add(ROOT / 'LICENSE', arcname='LICENSE')
        if 'deb' in formats:
            control = temp / 'control'
            control.mkdir()
            (control / 'control').write_text(
                f'Package: haneoka\nVersion: {args.version}\nArchitecture: {deb_arch}\n'
                'Maintainer: Haneoka contributors <noreply@haneoka.org>\n'
                'Section: games\nPriority: optional\n'
                'Depends: libgtk-3-0, libsecret-1-0, libstdc++6, libgstreamer1.0-0, '
                'libgstreamer-plugins-base1.0-0, libmpv2 | libmpv1, libjavascriptcoregtk-4.1-0\n'
                'Homepage: https://haneoka.org\nDescription: Our Notes catalogue and save reader\n')
            hashes = []
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    hashes.append(f'{hashlib.md5(path.read_bytes()).hexdigest()}  {path.relative_to(stage)}')
            (control / 'md5sums').write_text('\n'.join(hashes) + '\n')
            with (output / f'{name}.deb').open('wb') as package:
                package.write(b'!<arch>\n')
                debian_member(package, 'debian-binary', b'2.0\n')
                debian_member(package, 'control.tar.gz', compressed_tree(control))
                debian_member(package, 'data.tar.gz', compressed_tree(stage))
        if 'arch' in formats:
            info = stage / '.PKGINFO'
            info.write_text(f'pkgname = haneoka\npkgbase = haneoka\npkgver = {args.version}-1\n'
                            f'pkgdesc = Our Notes catalogue and save reader\narch = {architecture}\n'
                            f'builddate = {int(time.time())}\npackager = Haneoka contributors\n'
                            'url = https://haneoka.org\nlicense = MPL-2.0\n'
                            'depend = gtk3\ndepend = libsecret\ndepend = gstreamer\n'
                            'depend = gst-plugins-base-libs\ndepend = mpv\ndepend = webkit2gtk-4.1\n')
            run('tar', '--owner=0', '--group=0', '--zstd', '-cf', output / f'{name}.pkg.tar.zst', '-C', stage, '.PKGINFO', 'usr')
            info.unlink()
        if 'rpm' in formats:
            top = temp / 'rpm'
            for directory in ['BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS']:
                (top / directory).mkdir(parents=True)
            spec = top / 'SPECS/haneoka.spec'
            spec.write_text(f'Name: haneoka\nVersion: {args.version}\nRelease: 1\n'
                            'Summary: Our Notes catalogue and save reader\nLicense: MPL-2.0\n'
                            f'URL: https://haneoka.org\nBuildArch: {architecture}\n'
                            '%global debug_package %{nil}\n%global __strip /bin/true\n'
                            'Requires: gtk3, libsecret, gstreamer1, gstreamer1-plugins-base, mpv-libs, javascriptcoregtk4.1\n'
                            '%description\nOur Notes catalogue and local save reader.\n'
                            f'%install\nmkdir -p %{{buildroot}}\ncp -a "{stage}/usr" %{{buildroot}}/\n'
                            '%files\n/usr/bin/haneoka\n/usr/share/haneoka\n'
                            '/usr/share/applications/org.haneoka.haneoka.desktop\n'
                            '/usr/share/icons/hicolor/512x512/apps/org.haneoka.haneoka.png\n'
                            '/usr/share/mime/packages/org.haneoka.haneoka.xml\n')
            run('rpmbuild', '--define', f'_topdir {top}', '--define', '_build_id_links none', '-bb', spec)
            packages = list((top / 'RPMS').rglob('*.rpm'))
            if len(packages) != 1:
                raise SystemExit('Expected one RPM artifact')
            shutil.copy2(packages[0], output / f'{name}.rpm')
        if 'appimage' in formats:
            if not args.linuxdeploy:
                raise SystemExit('--linuxdeploy is required for AppImage')
            appdir = temp / 'Haneoka.AppDir'
            shutil.copytree(stage, appdir, symlinks=True)
            # linuxdeploy expects ELF executables in usr/bin. Keep the launcher
            # script for native packages, and point AppImage's entry to its ELF.
            entry = appdir / 'usr/bin/haneoka'
            entry.unlink()
            entry.symlink_to('../share/haneoka/haneoka')
            (appdir / 'AppRun').write_text('#!/bin/sh\nbase=$(dirname "$(readlink -f "$0")")\n'
                'export LD_LIBRARY_PATH="$base/usr/lib:$base/usr/share/haneoka/lib:${LD_LIBRARY_PATH:-}"\n'
                'exec "$base/usr/share/haneoka/haneoka" "$@"\n')
            (appdir / 'AppRun').chmod(0o755)
            candidates = list(Path('/usr/lib').glob('**/libmpv.so.2')) + list(Path('/usr/lib').glob('**/libmpv.so.1'))
            if not candidates:
                raise SystemExit('Install libmpv before creating AppImage')
            env = {**os.environ, 'APPIMAGE_EXTRACT_AND_RUN': '1', 'ARCH': architecture,
                   'OUTPUT': str(output / f'{name}.AppImage')}
            motion_sync = appdir / 'usr/share/haneoka/lib/libcubism_motion_sync.so'
            runtime_libraries = ['--library', motion_sync] if motion_sync.is_file() else []
            run(args.linuxdeploy.resolve(), '--appdir', appdir,
                '--executable', appdir / 'usr/share/haneoka/haneoka',
                '--desktop-file', appdir / desktop.relative_to(stage),
                '--icon-file', appdir / icon.relative_to(stage), '--library', candidates[0],
                *runtime_libraries, '--plugin', 'gtk', '--output', 'appimage', env=env)
        if 'snap' in formats:
            image = output / f'{name}.AppImage'
            if not image.exists():
                raise SystemExit('Create AppImage first so Snap includes the media/runtime libraries.')
            snap = temp / 'snap'
            snap.mkdir()
            run(image, '--appimage-extract', cwd=snap, stdout=subprocess.DEVNULL)
            extracted = snap / 'squashfs-root'
            shutil.move(str(extracted / 'usr'), snap / 'usr')
            shutil.rmtree(extracted)
            (snap / 'bin').mkdir()
            (snap / 'bin/haneoka').write_text('#!/bin/sh\n'
                'export LD_LIBRARY_PATH="$SNAP/usr/lib:$SNAP/usr/share/haneoka/lib:${LD_LIBRARY_PATH:-}"\n'
                'exec "$SNAP/usr/share/haneoka/haneoka" "$@"\n')
            (snap / 'bin/haneoka').chmod(0o755)
            (snap / 'meta').mkdir()
            (snap / 'meta/snap.yaml').write_text(f'name: haneoka\nversion: "{args.version}"\n'
                'summary: Our Notes catalogue and save reader\n'
                'description: Our Notes catalogue, community and local save reader.\n'
                f'architectures: [{deb_arch}]\nbase: core24\ngrade: stable\nconfinement: classic\n'
                'apps:\n  haneoka:\n    command: bin/haneoka\n'
                '    desktop: usr/share/applications/org.haneoka.haneoka.desktop\n')
            run('mksquashfs', snap, output / f'{name}.snap', '-noappend', '-comp', 'xz', '-all-root', '-processors', '2', '-mem', '256M')
    print(f'Created {", ".join(sorted(formats))}: {output}')


if __name__ == '__main__':
    main()
