/// Linux compute threads yield CPU priority to input and rendering. Their
/// affinity leaves one physical core (including its SMT sibling) available.
library;

import 'dart:ffi';
import 'dart:io';

final _configuredThreads = <int>{};
final _libc = Platform.isLinux ? DynamicLibrary.process() : null;
final _tid = _libc?.lookupFunction<Int32 Function(), int Function()>('gettid');
final _pid = _libc?.lookupFunction<Int32 Function(), int Function()>('getpid');
final _priority = _libc
    ?.lookupFunction<
      Int32 Function(Int32, Int32, Int32),
      int Function(int, int, int)
    >('setpriority');
final _getAffinity = _libc
    ?.lookupFunction<
      Int32 Function(Int32, IntPtr, Pointer<Uint8>),
      int Function(int, int, Pointer<Uint8>)
    >('sched_getaffinity');
final _setAffinity = _libc
    ?.lookupFunction<
      Int32 Function(Int32, IntPtr, Pointer<Uint8>),
      int Function(int, int, Pointer<Uint8>)
    >('sched_setaffinity');
final _malloc = _libc
    ?.lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');
final _free = _libc
    ?.lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');
List<int>? _computeMask;

void computeThreadPolicy() {
  if (!Platform.isLinux ||
      Platform.environment['HANEOKA_COMPUTE_PROCESS'] == '1') {
    return;
  }
  final tid = _tid!();
  if (!_configuredThreads.add(tid)) return;
  _priority!(0, tid, 8);
  final mask = _malloc!(128);
  if (mask == nullptr) return;
  try {
    final bytes = mask.asTypedList(128);
    if (_computeMask == null) {
      if (_getAffinity!(_pid!(), 128, mask) != 0) return;
      final allowed = [
        for (var cpu = 0; cpu < 1024; cpu++)
          if (bytes[cpu ~/ 8] & (1 << (cpu % 8)) != 0) cpu,
      ];
      if (allowed.length < 2) return;
      String physicalCore(int cpu) {
        try {
          final base = '/sys/devices/system/cpu/cpu$cpu/topology';
          return '${File('$base/physical_package_id').readAsStringSync().trim()}:${File('$base/core_id').readAsStringSync().trim()}';
        } catch (_) {
          return '$cpu';
        }
      }

      final reserved = physicalCore(allowed.first);
      final compute = allowed
          .where((cpu) => physicalCore(cpu) != reserved)
          .toList();
      if (compute.isEmpty) return;
      bytes.fillRange(0, 128, 0);
      for (final cpu in compute) {
        bytes[cpu ~/ 8] |= 1 << (cpu % 8);
      }
      _computeMask = bytes.toList();
    }
    bytes.setAll(0, _computeMask!);
    _setAffinity!(tid, 128, mask);
  } finally {
    _free!(mask);
  }
}
