// Memory of the decoder and the spelling index (OcrFix), measured on this computer's Dart VM.
//
//   ~/development/flutter/bin/dart run --enable-vm-service --disable-service-auth-codes \
//       tool/memory_bench.dart [old|new|decoder]
//
// "old" is how the app built the spelling index before (a second Decoder.fromJson in another isolate), "new" is
// OcrFix.build from the loaded decoder, "decoder" is the decoder alone. Prints the Dart heap in use after a full
// garbage collection, the process RSS, and the peak RSS. Run each mode in its own process.
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/engine/ocr_fix.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'new' : args.first;
  final a = File('assets/data/decoder.json').readAsStringSync();
  final b = File('assets/data/decoder-data.json').readAsStringSync();
  final c = File('assets/data/inci-vocab.json').readAsStringSync();
  final d = await Isolate.run(() => Decoder.fromJson(a, b, c));
  OcrFix? fix;
  final sw = Stopwatch()..start();
  if (mode == 'old') {
    fix = await Isolate.run(() => OcrFix(Decoder.fromJson(a, b, c)));
  } else if (mode == 'new') {
    fix = await OcrFix.build(d);
  }
  final buildMs = sw.elapsedMilliseconds;
  final text = List.filled(3, 'Water, Lim0nene, Methylparabn, Citric Acid, Sodium Laureth Sulfale, Parfurn, Glycerin, '
          'Cetearyl Alcohoi, Xanthan Gurn, Panthenoi, Sodiurn Benzoate')
      .join(', ');
  var suggestMs = 0.0;
  if (fix != null) {
    fix.suggest(text);
    sw.reset();
    fix.suggest(text);
    suggestMs = sw.elapsedMicroseconds / 1000;
  }
  final heap = await _heapAfterGc();
  String mb(int n) => '${(n / 1048576).toStringAsFixed(1)} MB';
  print('$mode: heap after GC ${heap == 0 ? '(run with --enable-vm-service)' : mb(heap)}, '
      'RSS ${mb(ProcessInfo.currentRss)}, peak RSS ${mb(ProcessInfo.maxRss)}, build $buildMs ms, '
      'suggest (33 items, warm) ${suggestMs.toStringAsFixed(1)} ms, '
      'index arrays ${mode == 'new' ? mb(fix!.arrayBytes) : '-'}, ${d.vocab.length} names in the vocabulary');
  exit(0);
}

Future<int> _heapAfterGc() async {
  final info = await Service.getInfo();
  if (info.serverWebSocketUri == null) return 0;
  final vm = await vmServiceConnectUri(info.serverWebSocketUri.toString());
  final p = await vm.getAllocationProfile(Service.getIsolateId(Isolate.current)!, gc: true);
  await vm.dispose();
  return (p.memoryUsage!.heapUsage ?? 0) + (p.memoryUsage!.externalUsage ?? 0);
}
