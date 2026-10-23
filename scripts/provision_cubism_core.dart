import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const _sdkName = 'CubismSdkForNative-5-r.5';
const _sdkUrl = 'https://cubism.live2d.com/sdk-native/bin/$_sdkName.zip';
const _sdkSha256 =
    '7ff3a4bbc19c0a8728965aa522ab77eb11b252916453e68a8a78d3b71188bb12';

/// Provisions the pinned native Core into the resolved Cubism provider package.
/// Run after `flutter pub get`, before the platform build.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(
      'dart run scripts/provision_cubism_core.dart '
      '--platform <linux|windows|android|macos|ios> '
      '[--arch <x64|arm64|x86>] [--archive <SDK zip>] '
      '[--cache <directory>] [--package-config <package_config.json>]',
    );
    return;
  }
  var platform = Platform.operatingSystem;
  String? arch;
  String? archivePath;
  var cache = 'build/player-runtimes';
  var packageConfig = '.dart_tool/package_config.json';
  for (var index = 0; index < arguments.length; index++) {
    final option = arguments[index];
    if (index + 1 == arguments.length) {
      throw ArgumentError('Missing value for $option');
    }
    final value = arguments[++index];
    switch (option) {
      case '--platform':
        platform = value;
      case '--arch':
        arch = value;
      case '--archive':
        archivePath = value;
      case '--cache':
        cache = value;
      case '--package-config':
        packageConfig = value;
      default:
        throw ArgumentError('Unknown option: $option');
    }
  }
  if (!{'linux', 'windows', 'android', 'macos', 'ios'}.contains(platform)) {
    throw ArgumentError('Unsupported Cubism platform: $platform');
  }
  arch ??= switch (Abi.current()) {
    Abi.androidArm64 ||
    Abi.iosArm64 ||
    Abi.linuxArm64 ||
    Abi.macosArm64 ||
    Abi.windowsArm64 => 'arm64',
    Abi.androidIA32 || Abi.linuxIA32 || Abi.windowsIA32 => 'x86',
    _ => 'x64',
  };
  if (!{'x64', 'arm64', 'x86'}.contains(arch)) {
    throw ArgumentError('Unsupported Cubism architecture: $arch');
  }
  if (platform == 'linux' && arch == 'x86') {
    throw StateError('Cubism Native R5 has no Linux x86 Core');
  }
  final configuration = File(packageConfig).absolute;
  final packages =
      (jsonDecode(await configuration.readAsString())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final provider = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'vega_plugin_cubism',
  );
  final providerUri = provider['rootUri'] as String;
  final providerRoot = configuration.uri.resolve(
    providerUri.endsWith('/') ? providerUri : '$providerUri/',
  );
  final provision = File.fromUri(providerRoot.resolve('tool/provision.dart'));
  if (!await provision.exists()) {
    throw StateError('Cubism provider has no tool/provision.dart');
  }
  final directory = Directory(cache).absolute;
  await directory.create(recursive: true);
  final zip = File(archivePath ?? '${directory.path}/$_sdkName.zip');
  if (!await zip.exists()) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_sdkUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Cubism SDK HTTP ${response.statusCode}');
      }
      final temporary = File('${zip.path}.download');
      await temporary.parent.create(recursive: true);
      await response.pipe(temporary.openWrite());
      await temporary.rename(zip.path);
    } finally {
      client.close();
    }
  }
  final digest = (await sha256.bind(zip.openRead()).first).toString();
  if (digest != _sdkSha256) {
    throw StateError('Cubism SDK SHA256 mismatch: $digest');
  }
  final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  final sdk = Directory('${directory.path}/$_sdkName');
  var extracted = 0;
  for (final entry in archive.files) {
    if (!entry.isFile || entry.isSymbolicLink) continue;
    if (!entry.name.startsWith('$_sdkName/Core/') &&
        entry.name != '$_sdkName/LICENSE.md' &&
        entry.name != '$_sdkName/NOTICE.md') {
      continue;
    }
    final segments = entry.name.split('/');
    if (segments.any((segment) => segment == '..' || segment.contains('\\'))) {
      throw StateError('Invalid SDK archive path: ${entry.name}');
    }
    final output = File('${directory.path}/${entry.name}');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(entry.content);
    extracted++;
  }
  final requiredCore = switch (platform) {
    'linux' when arch == 'arm64' =>
      'Core/dll/experimental/linux/arm64/libLive2DCubismCore.so',
    'linux' => 'Core/dll/linux/x86_64/libLive2DCubismCore.so',
    'windows' when arch == 'arm64' => throw StateError(
      'Cubism Native R5 has no desktop Windows ARM64 Core; '
      'use the complete Windows x64 package on Windows 11 ARM64.',
    ),
    'windows' when arch == 'x86' => 'Core/dll/windows/x86/Live2DCubismCore.dll',
    'windows' => 'Core/dll/windows/x86_64/Live2DCubismCore.dll',
    'android' => 'Core/dll/android/arm64-v8a/libLive2DCubismCore.so',
    'macos' => 'Core/dll/macos/libLive2DCubismCore.dylib',
    'ios' => 'Core/lib/ios/Release-iphoneos/libLive2DCubismCore.a',
    _ => throw StateError('Unsupported Cubism target: $platform/$arch'),
  };
  final core = File('${sdk.path}/$requiredCore');
  if (!await core.exists()) {
    throw StateError('Pinned SDK misses $requiredCore');
  }
  final hostArch = switch (Abi.current()) {
    Abi.linuxArm64 || Abi.macosArm64 || Abi.windowsArm64 => 'arm64',
    Abi.windowsIA32 => 'x86',
    _ => 'x64',
  };
  int? coreVersion;
  if (platform == Platform.operatingSystem &&
      arch == hostArch &&
      platform != 'android') {
    final library = DynamicLibrary.open(core.path);
    coreVersion = library.lookupFunction<Uint32 Function(), int Function()>(
      'csmGetVersion',
    )();
    if (coreVersion == 0) throw StateError('Cubism Core returned no version');
  }
  final result = await Process.start(Platform.resolvedExecutable, [
    provision.path,
    '--sdk',
    sdk.path,
    '--platform',
    platform,
  ], mode: ProcessStartMode.inheritStdio);
  if (await result.exitCode != 0) {
    throw StateError('Cubism provider provisioning failed');
  }
  stdout.writeln(
    jsonEncode({
      'sdk': _sdkName,
      'sdkSha256': digest,
      'provider': providerRoot.toString(),
      'platform': platform,
      'arch': arch,
      'coreSha256': (await sha256.bind(core.openRead()).first).toString(),
      'coreVersion': coreVersion,
      'extracted': extracted,
    }),
  );
}
