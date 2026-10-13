/// The Rust lottery kernel is loaded only by compute workers. Linux runs those
/// workers in its independent helper process, outside Flutter's UI runtime.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'num.dart';

class _Kernel {
  _Kernel() {
    final directory = File(Platform.resolvedExecutable).parent.path;
    final library = DynamicLibrary.open(
      '$directory/lib/libhaneoka_team_engine.so',
    );
    run = library
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Uint8>),
          Pointer<Uint8> Function(Pointer<Uint8>)
        >('haneoka_luck_json');
    release = library
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('haneoka_string_free');
    final libc = DynamicLibrary.process();
    allocate = libc
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr),
          Pointer<Uint8> Function(int)
        >('malloc');
    free = libc
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
  }
  late final Pointer<Uint8> Function(Pointer<Uint8>) run;
  late final void Function(Pointer<Uint8>) release;
  late final void Function() cancel;
  late final Pointer<Uint8> Function(int) allocate;
  late final void Function(Pointer<Uint8>) free;
}

final _Kernel? _kernel = Platform.isLinux ? _Kernel() : null;
bool get nativeLuckAvailable => Platform.isLinux;
void cancelNativeComputations() => _kernel?.cancel();

Doc nativeLuck(Doc input) {
  final kernel = _kernel!;
  final bytes = utf8.encode(jsonEncode(input));
  final pointer = kernel.allocate(bytes.length + 1);
  if (pointer == nullptr) throw StateError('native-luck-allocation');
  Pointer<Uint8> result = nullptr;
  try {
    pointer.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    result = kernel.run(pointer);
    if (result == nullptr) throw StateError('native-luck-result');
    var length = 0;
    while (result[length] != 0) {
      length++;
    }
    final output = objectRow(
      jsonDecode(utf8.decode(result.asTypedList(length))),
    );
    if (output['error'] != null) throw StateError('${output['error']}');
    return output;
  } finally {
    if (result != nullptr) kernel.release(result);
    kernel.free(pointer);
  }
}
