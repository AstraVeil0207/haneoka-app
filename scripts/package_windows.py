#!/usr/bin/env python3
"""Create portable ZIP, Inno Setup EXE and WiX MSI from a Flutter bundle."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NS = 'http://wixtoolset.org/schemas/v4/wxs'
ET.register_namespace('', NS)


def node(parent, name, **attributes):
    return ET.SubElement(parent, f'{{{NS}}}{name}', attributes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--arch', choices=['x64', 'arm64'], required=True)
    parser.add_argument('--out', type=Path, default=ROOT / 'dist')
    parser.add_argument('--iscc', default='ISCC.exe')
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    if not (bundle / 'haneoka.exe').exists() or not (bundle / 'tools/adb/adb.exe').exists():
        raise SystemExit('Build the app and bundle ADB first')
    with (bundle / 'haneoka.exe').open('rb') as executable:
        header = executable.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise SystemExit('Expected a PE Windows application')
        executable.seek(int.from_bytes(header[60:64], 'little'))
        signature = executable.read(6)
    if signature[:4] != b'PE\x00\x00' or int.from_bytes(signature[4:6], 'little') != (0x8664 if args.arch == 'x64' else 0xaa64):
        raise SystemExit('Windows executable architecture does not match the package architecture')
    args.out.mkdir(parents=True, exist_ok=True)
    output = args.out.resolve()
    name = f'haneoka-windows-{args.arch}'
    with zipfile.ZipFile(output / f'{name}.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(bundle.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(bundle))
        archive.write(ROOT / 'LICENSE', 'LICENSE')
    work = ROOT / 'build' / 'packaging' / f'windows-{args.arch}'
    work.mkdir(parents=True, exist_ok=True)
    inno = work / 'haneoka.iss'
    architecture = 'x64compatible' if args.arch == 'x64' else 'arm64'
    inno.write_text(f'''[Setup]
AppId={{{{536BA31B-4E70-471D-B7AD-8F16F7CF7A72}}
AppName=Haneoka
AppVersion={args.version}
AppPublisher=Haneoka contributors
AppPublisherURL=https://haneoka.org
DefaultDirName={{localappdata}}\\Programs\\Haneoka
DefaultGroupName=Haneoka
PrivilegesRequired=lowest
ArchitecturesAllowed={architecture}
ArchitecturesInstallIn64BitMode={architecture}
OutputDir={output}
OutputBaseFilename={name}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={{app}}\\haneoka.exe
ChangesAssociations=yes
[Files]
Source: "{bundle}\\*"; DestDir: "{{app}}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{ROOT / 'LICENSE'}"; DestDir: "{{app}}"; Flags: ignoreversion
[Icons]
Name: "{{group}}\\Haneoka"; Filename: "{{app}}\\haneoka.exe"
[Registry]
Root: HKCU; Subkey: "Software\\Classes\\Haneoka.Save"; ValueType: string; ValueData: "Haneoka save archive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\Haneoka.Save\\shell\\open\\command"; ValueType: string; ValueData: """{{app}}\\haneoka.exe"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\.haneoka-save"; ValueType: string; ValueData: "Haneoka.Save"; Flags: uninsdeletevalue
[Run]
Filename: "{{app}}\\haneoka.exe"; Description: "Open Haneoka"; Flags: nowait postinstall skipifsilent
''')
    subprocess.run([args.iscc, str(inno)], check=True)
    wix = ET.Element(f'{{{NS}}}Wix')
    package = node(wix, 'Package', Name='Haneoka', Manufacturer='Haneoka contributors',
                   Version=args.version, UpgradeCode='536BA31B-4E70-471D-B7AD-8F16F7CF7A72', Scope='perUser')
    node(package, 'MajorUpgrade', DowngradeErrorMessage='A newer Haneoka version is already installed.')
    node(package, 'MediaTemplate', EmbedCab='yes')
    local = node(package, 'StandardDirectory', Id='LocalAppDataFolder')
    programs = node(local, 'Directory', Id='UserPrograms', Name='Programs')
    install = node(programs, 'Directory', Id='INSTALLFOLDER', Name='Haneoka')
    directories = {Path('.'): install}
    feature = node(package, 'Feature', Id='Application', Title='Haneoka', Level='1')
    namespace = uuid.UUID('536ba31b-4e70-471d-b7ad-8f16f7cf7a72')
    files = [(file.relative_to(bundle), file) for file in sorted(bundle.rglob('*')) if file.is_file()]
    files.append((Path('LICENSE'), ROOT / 'LICENSE'))
    for relative, source in files:
        parent = Path('.')
        for part in relative.parent.parts:
            path = parent / part
            if path not in directories:
                identifier = 'D' + hashlib.sha256(str(path).encode()).hexdigest()[:24]
                directories[path] = node(directories[parent], 'Directory', Id=identifier, Name=part)
            parent = path
        identifier = hashlib.sha256(str(relative).encode()).hexdigest()[:24]
        component = node(directories[parent], 'Component', Id='C' + identifier,
                         Guid=str(uuid.uuid5(namespace, args.arch + '/' + str(relative))), Bitness='always64')
        payload = node(component, 'File', Id='F' + identifier, Source=str(source), KeyPath='no')
        node(component, 'RegistryValue', Root='HKCU', Key='Software\\Haneoka\\Installer',
             Name=identifier, Type='string', Value=args.version, KeyPath='yes')
        if relative.name == 'haneoka.exe':
            node(payload, 'Shortcut', Id='StartMenuShortcut', Directory='ProgramMenuFolder',
                 Name='Haneoka', Advertise='no')
        node(feature, 'ComponentRef', Id='C' + identifier)
    association = node(install, 'Component', Id='SaveAssociation',
                       Guid=str(uuid.uuid5(namespace, 'save-association')), Bitness='always64')
    node(association, 'RegistryValue', Root='HKCU', Key='Software\\Classes\\.haneoka-save',
         Type='string', Value='Haneoka.Save', KeyPath='yes')
    node(association, 'RegistryValue', Root='HKCU', Key='Software\\Classes\\Haneoka.Save\\shell\\open\\command',
         Type='string', Value='"[INSTALLFOLDER]haneoka.exe" "%1"')
    node(feature, 'ComponentRef', Id='SaveAssociation')
    node(package, 'StandardDirectory', Id='ProgramMenuFolder')
    source = work / 'haneoka.wxs'
    ET.ElementTree(wix).write(source, encoding='utf-8', xml_declaration=True)
    subprocess.run(['wix', 'build', str(source), '-arch', args.arch,
                    '-o', str(output / f'{name}.msi')], check=True)
    print(f'Created ZIP, EXE, MSI: {output}')


if __name__ == '__main__':
    main()
