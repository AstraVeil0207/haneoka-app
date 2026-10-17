import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

int _active = 0;
final _waiters = Queue<Completer<void>>();

/// Shares two CPU workers. [compute] owns only sendable data; [checkCurrent]
/// stays in the calling isolate and checks cancellation around queued work.
Future<T> runBackgroundWork<T>(
  T Function() compute, {
  required void Function() checkCurrent,
  String? debugName,
}) async {
  checkCurrent();
  if (_active >= 2) {
    final slot = Completer<void>();
    _waiters.add(slot);
    await slot.future;
  } else {
    _active++;
  }
  try {
    checkCurrent();
    final result = await Isolate.run(compute, debugName: debugName);
    checkCurrent();
    return result;
  } finally {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
