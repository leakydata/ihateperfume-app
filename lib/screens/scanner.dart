/// The scanner: barcode (ML Kit barcode scanning) or ingredient list (camera photo + ML Kit text recognition).
/// Both run on the phone. Only a barcode number is ever sent anywhere, to Open Beauty Facts, Open Products Facts,
/// the FDA's openFDA service, and ihateperfume.com (our own reviewed products). "Add it" opens the submission
/// screen, which sends photos only when the user taps Send.
library;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services.dart';
import '../theme.dart';
import 'contribute.dart';
import 'ingredient.dart' show openLink;
import 'no_list.dart';
import 'result.dart';
import 'review.dart';

enum ScanMode { barcode, list }

void openScanner(BuildContext context, ScanMode mode) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerScreen(mode: mode)));

class ScannerScreen extends StatefulWidget {
  final ScanMode mode;
  const ScannerScreen({super.key, required this.mode});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  late ScanMode _mode = widget.mode;
  String? _busy; // message while looking up or reading
  String? _notice; // e.g. "not found, photograph the list"
  (String, String)? _maker; // the maker's ingredient page for the barcode in the notice, opened only on tap
  String? _barcode; // carried into the photo step when a barcode had no ingredient list
  String? _name;
  bool _torch = false;
  bool _covered = false; // the "Add it" screen is on top and may be using the camera

  MobileScannerController? _scanner;
  CameraController? _camera;
  String? _cameraError;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner?.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The photo camera must be released when the app is in the background (the barcode scanner handles itself).
    if (_mode != ScanMode.list) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _camera;
      _camera = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null && !_covered) {
      _initCamera();
    }
  }

  Future<void> _startMode() async {
    _torch = false;
    if (_mode == ScanMode.barcode) {
      final c = _camera;
      _camera = null;
      await c?.dispose();
      _scanner ??= MobileScannerController(
        formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    } else {
      final s = _scanner;
      _scanner = null;
      await s?.dispose();
      await _initCamera();
    }
    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted || _mode != ScanMode.list) {
        await c.dispose();
        return;
      }
      setState(() {
        _camera = c;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError = e.code == 'CameraAccessDenied' || e.code.contains('Denied')
            ? 'The camera is off for this app. You can turn it on in Settings, or type the list instead.'
            : 'The camera couldn’t start (${e.description ?? e.code}).');
      }
    }
  }

  void _switch(ScanMode m) {
    if (m == _mode || _busy != null) return;
    setState(() {
      _mode = m;
      _notice = null;
      _maker = null;
    });
    _startMode();
  }

  // ---------- barcode ----------

  Future<void> _onBarcode(BarcodeCapture cap) async {
    if (_handling) return;
    final code = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstWhere(
          (v) => RegExp(r'^\d{6,14}$').hasMatch(v),
          orElse: () => '',
        );
    if (code.isEmpty) return;
    _handling = true;
    HapticFeedback.mediumImpact();
    await _scanner?.stop();
    await _lookUp(code);
  }

  Future<void> _lookUp(String code) async {
    setState(() {
      _busy = 'Looking up $code';
      _maker = null;
    });
    try {
      final p = await lookUp(code);
      if (!mounted) return;
      if (p?.ingredients != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ResultScreen(
                text: p!.ingredients!, name: p.name, barcode: code, source: p.source, ihp: p.ihp, save: true)));
        return;
      }
      if (p != null && p.noList) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => NoListScreen(name: p.name, barcode: code, info: p.ihp!, save: true)));
        return;
      }
      setState(() {
        _busy = null;
        _barcode = code;
        _name = p?.name.isNotEmpty == true ? p!.name : null;
        _notice = p == null
            ? 'Barcode $code isn’t in Open Beauty Facts, Open Products Facts, the FDA’s drug labels, or ours. '
                'Photograph the ingredient list instead.'
            : p.source == 'fda'
                ? 'The FDA drug label for ${p.name.isEmpty ? 'this product' : p.name} has no inactive ingredient list. '
                    'Photograph the list instead.'
                : '${p.sourceName} knows ${p.name.isEmpty ? 'this product' : p.name}, but not its ingredients. Photograph the list instead.';
        _maker = makerPage(code);
        _mode = ScanMode.list;
      });
      _handling = false;
      await _startMode();
    } on LookupError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _notice = '${e.message} Or photograph the ingredient list: that works offline.';
      });
      _handling = false;
      await _scanner?.start();
    }
  }

  Future<void> _typeBarcode() async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Big('Type the barcode', size: 26),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
          style: T.mono(size: 18, weight: FontWeight.w400),
          decoration: const InputDecoration(hintText: 'The numbers under the bars'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Mono('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Mono('Look it up', color: C.signal)),
        ],
      ),
    );
    if (code == null || code.length < 6 || !mounted) return;
    _handling = true;
    await _scanner?.stop();
    await _lookUp(code);
  }

  // ---------- ingredient list ----------

  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _busy != null) return;
    setState(() => _busy = 'Reading the list\non your phone');
    try {
      final shot = await c.takePicture();
      if (_torch) await c.setFlashMode(FlashMode.off);
      _torch = false;
      await _read(shot.path, delete: true);
    } on CameraException catch (e) {
      if (mounted) setState(() => _busy = null);
      _snack('Couldn’t take the photo (${e.code}).');
    }
  }

  Future<void> _fromPhotos() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null || !mounted) return;
    setState(() => _busy = 'Reading the list\non your phone');
    // The picker hands us a copy in the app's own cache: delete that copy after reading, never the original.
    await _read(x.path, delete: x.path.contains('/com.ihateperfume.ihateperfume/cache/'));
  }

  Future<void> _read(String path, {required bool delete}) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    String text;
    try {
      text = (await rec.processImage(InputImage.fromFilePath(path))).text;
    } finally {
      await rec.close();
      // Our own photo is deleted as soon as it's read; nothing is kept or sent.
      if (delete) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (text.trim().isEmpty) {
      _snack('No text found. Get closer, hold steady, and try the flash.');
      return;
    }
    _openReview(cleanOcr(text), ReviewKind.photo);
  }

  /// "Add it": send us this product. The camera is let go first, so the photo step can use it.
  Future<void> _addIt() async {
    _covered = true;
    final c = _camera;
    _camera = null;
    await c?.dispose();
    await _scanner?.stop();
    if (!mounted) return;
    setState(() {});
    await openContribute(context, barcode: _barcode, name: _name);
    _covered = false;
    if (mounted) await _startMode();
  }

  void _openReview(String text, ReviewKind kind) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewScreen(text: text, kind: kind, barcode: _barcode, name: _name)));

  Future<void> _toggleTorch() async {
    try {
      if (_mode == ScanMode.barcode) {
        await _scanner?.toggleTorch();
      } else {
        await _camera?.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      }
      setState(() => _torch = !_torch);
    } catch (_) {
      _snack('This camera has no flash.');
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Row(children: [
                InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                      padding: EdgeInsets.fromLTRB(0, 10, 14, 10), child: Icon(Icons.arrow_back, size: 20, color: C.paper)),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: C.paper, width: 2)),
                    child: Row(children: [
                      _seg('Barcode', ScanMode.barcode),
                      _seg('Ingredient list', ScanMode.list),
                    ]),
                  ),
                ),
              ]),
            ),
            Expanded(child: _viewfinder()),
            SizedBox(
              height: 130,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _textBtn(_torch ? 'Flash on' : 'Flash', _toggleTorch),
                _shutter(),
                _textBtn('Type it', () {
                  if (_mode == ScanMode.barcode) {
                    _typeBarcode();
                  } else {
                    _openReview('', ReviewKind.typed);
                  }
                }),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _seg(String label, ScanMode m) => Expanded(
        child: InkWell(
          onTap: () => _switch(m),
          child: Container(
            color: _mode == m ? C.paper : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Mono(label, color: _mode == m ? C.ink : C.paper, align: TextAlign.center),
          ),
        ),
      );

  Widget _textBtn(String label, VoidCallback onTap) => InkWell(
        onTap: _busy == null ? onTap : null,
        child: SizedBox(width: 90, height: 60, child: Center(child: Mono(label, color: C.paper))),
      );

  Widget _shutter() {
    final list = _mode == ScanMode.list;
    return Semantics(
      button: true,
      label: list ? 'Take the photo' : 'Scanning for a barcode',
      child: GestureDetector(
        onTap: list ? _shoot : null,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: list ? C.paper : const Color(0xFF666666), width: 5),
            color: list ? C.signal : const Color(0xFF3A1A12),
          ),
        ),
      ),
    );
  }

  Widget _viewfinder() {
    final list = _mode == ScanMode.list;
    Widget preview;
    if (list) {
      final c = _camera;
      preview = c != null && c.value.isInitialized
          ? ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            )
          : _placeholder(_cameraError);
    } else {
      preview = _scanner == null
          ? _placeholder(null)
          : MobileScanner(
              controller: _scanner,
              onDetect: _onBarcode,
              errorBuilder: (context, e) => _placeholder(e.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'The camera is off for this app. You can turn it on in Settings, or type the barcode instead.'
                  : 'The camera couldn’t start (${e.errorCode.name}).'),
            );
    }
    return LayoutBuilder(builder: (context, box) {
      final fw = (box.maxWidth - 80).clamp(200.0, 320.0);
      final fh = list ? (box.maxHeight * .58).clamp(200.0, 420.0) : 170.0;
      return Stack(fit: StackFit.expand, children: [
        preview,
        Center(
          child: Transform.translate(
            offset: Offset(0, -box.maxHeight * .06),
            child: SizedBox(
              width: fw,
              height: fh,
              child: CustomPaint(painter: _Brackets(scanLine: !list)),
            ),
          ),
        ),
        if (_notice != null)
          Positioned(
            left: 20,
            right: 20,
            top: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: C.label, border: Border(left: BorderSide(color: C.signal, width: 6))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_notice!, style: T.lede.copyWith(fontSize: 14)),
                Wrap(spacing: 18, children: [
                  if (_barcode != null)
                    InkWell(
                      onTap: _busy == null ? _addIt : null,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 2),
                        child: MonoLink('Add it', icon: Icons.arrow_forward, size: 11),
                      ),
                    ),
                  if (_maker != null)
                    InkWell(
                      onTap: () => openLink(context, _maker!.$1),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: MonoLink(_maker!.$2, size: 11),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 22,
          child: Column(children: [
            Mono(list ? 'Fill the frame with the ingredient list' : 'Point at the barcode',
                size: 13, color: C.paper, align: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              list
                  ? 'Read on your phone. The photo never leaves it.'
                  : 'Read on your phone. Only the barcode number is sent, to look the product up.',
              textAlign: TextAlign.center,
              style: T.src(size: 12, color: const Color(0xFFBBBBBB)),
            ),
            if (list) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: _busy == null ? _fromPhotos : null,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Mono('Or pick a photo you took', size: 11, color: C.signalLight),
                ),
              ),
            ],
          ]),
        ),
        if (_busy != null)
          Container(
            color: const Color(0xCC000000),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                  width: 34, height: 34, child: CircularProgressIndicator(color: C.signal, strokeWidth: 4)),
              const SizedBox(height: 18),
              Mono(_busy!, size: 13, color: C.paper, align: TextAlign.center),
            ]),
          ),
      ]);
    });
  }

  Widget _placeholder(String? error) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B3A37), Color(0xFF1B1A19)]),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: error == null ? null : Text(error, textAlign: TextAlign.center, style: T.lede.copyWith(color: C.paper)),
      );
}

/// Red corner brackets, and a scan line for barcodes.
class _Brackets extends CustomPainter {
  final bool scanLine;
  _Brackets({required this.scanLine});
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = C.signal
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final ax = s.width * .22, ay = s.height * .3;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1, 1), (s.width, 0.0, -1, 1), (0.0, s.height, 1, -1), (s.width, s.height, -1, -1)]) {
      canvas.drawPath(
          Path()
            ..moveTo(x + dx * ax, y + dy * 2)
            ..lineTo(x + dx * 2, y + dy * 2)
            ..lineTo(x + dx * 2, y + dy * ay),
          p);
    }
    if (scanLine) {
      final y = s.height / 2;
      canvas.drawRect(Rect.fromLTRB(24, y - 1.5, s.width - 24, y + 1.5),
          Paint()
            ..color = C.signal
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      canvas.drawRect(Rect.fromLTRB(24, y - 1.5, s.width - 24, y + 1.5), Paint()..color = C.signal);
    }
  }

  @override
  bool shouldRepaint(_Brackets old) => old.scanLine != scanLine;
}
