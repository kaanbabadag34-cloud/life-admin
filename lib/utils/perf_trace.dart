import 'package:flutter/foundation.dart';

// Aşama süresi ölçümü (yalnızca log; metin/kişisel veri İÇERMEZ). Çıktı:
// [Perf] ai-add: parse-plan=820ms insert=140ms reload=95ms total=1070ms
class PerfTrace {
  PerfTrace(this.name) : _watch = Stopwatch()..start();

  final String name;
  final Stopwatch _watch;
  final List<String> _marks = [];
  int _last = 0;

  void mark(String stage) {
    final now = _watch.elapsedMilliseconds;
    _marks.add('$stage=${now - _last}ms');
    _last = now;
  }

  void finish() {
    debugPrint(
      '[Perf] $name: ${_marks.join(' ')} total=${_watch.elapsedMilliseconds}ms',
    );
  }
}
