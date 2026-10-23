import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/detail.dart';

class ModelViewTransform extends TransformationController {
  Size viewport = Size.zero;
  double get zoom => value.getMaxScaleOnAxis();
  void setZoom(double zoom) {
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final ratio = zoom / this.zoom;
    value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(value);
  }

  void reset() => value = Matrix4.identity();
}

/// Both native model runtimes share framing, gestures and transparent capture.
class ModelViewport extends StatelessWidget {
  const ModelViewport({
    super.key,
    required this.captureKey,
    required this.transform,
    required this.painter,
    this.onLook,
    this.onLookEnd,
    this.drag = true,
    this.onViewport,
  });
  final GlobalKey captureKey;
  final ModelViewTransform transform;
  final CustomPainter painter;
  final ValueChanged<Offset>? onLook;
  final VoidCallback? onLookEnd;
  final bool drag;
  final ValueChanged<Size>? onViewport;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      transform.viewport = constraints.biggest;
      onViewport?.call(constraints.biggest);
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: MouseRegion(
          onHover: onLook == null
              ? null
              : (event) => onLook!(
                  Offset(
                    event.localPosition.dx / constraints.maxWidth * 2 - 1,
                    1 - event.localPosition.dy / constraints.maxHeight * 2,
                  ),
                ),
          onExit: (_) => onLookEnd?.call(),
          child: RepaintBoundary(
            key: captureKey,
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: transform,
                panEnabled: drag,
                scaleEnabled: drag,
                minScale: .25,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: CustomPaint(size: constraints.biggest, painter: painter),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<Uint8List> captureModelPng(GlobalKey key) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final size = boundary.size;
  final ratio = modelCaptureRatio(size);
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

double modelCaptureRatio(Size size) => math.sqrt(4000000 / (size.width * size.height)).clamp(.25, 4.0);

Future<void> saveModelFile(String name, Uint8List bytes) async {
  await FilePicker.saveFile(fileName: name, bytes: bytes);
}

class ModelTransformSettings extends StatelessWidget {
  const ModelTransformSettings({super.key, required this.transform});
  final ModelViewTransform transform;
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return DetailSection(
      title: t('media.models.labels.transform', 'Transform'),
      icon: Symbols.open_with_rounded,
      child: ListenableBuilder(
        listenable: transform,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('media.models.labels.zoom', 'Zoom')),
            Slider(
              value: transform.zoom.clamp(.25, 4),
              min: .25,
              max: 4,
              label: '${transform.zoom.toStringAsFixed(2)}×',
              onChanged: transform.setZoom,
            ),
            TextButton.icon(
              icon: const Icon(Symbols.restart_alt_rounded),
              label: Text(
                t(
                  'media.models.labels.resetTransform',
                  'Reset position and zoom',
                ),
              ),
              onPressed: transform.reset,
            ),
          ],
        ),
      ),
    );
  }
}

class ModelBackgroundSetting extends StatelessWidget {
  const ModelBackgroundSetting({
    super.key,
    required this.color,
    required this.onChanged,
  });
  final Color? color;
  final ValueChanged<Color?> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return Row(
      children: [
        Expanded(
          child: Text(
            t('media.models.labels.backgroundColor', 'Background color'),
          ),
        ),
        IconButton(
          tooltip: t('media.models.labels.backgroundColor', 'Background color'),
          onPressed: color == null
              ? null
              : () async {
                  final result = await showDialog<Color>(
                    context: context,
                    builder: (context) =>
                        _BackgroundDialog(initial: color!, text: t),
                  );
                  if (result != null) onChanged(result);
                },
          icon: Icon(Symbols.palette_rounded, color: color),
        ),
        Switch(
          value: color != null,
          onChanged: (value) =>
              onChanged(value ? Theme.of(context).colorScheme.surface : null),
        ),
      ],
    );
  }
}

class _BackgroundDialog extends StatefulWidget {
  const _BackgroundDialog({required this.initial, required this.text});
  final Color initial;
  final SiteText text;
  @override
  State<_BackgroundDialog> createState() => _BackgroundDialogState();
}

class _BackgroundDialogState extends State<_BackgroundDialog> {
  late final channels = [widget.initial.r, widget.initial.g, widget.initial.b];
  Color get color => Color.from(
    alpha: 1,
    red: channels[0],
    green: channels[1],
    blue: channels[2],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.text('media.models.labels.backgroundColor', 'Background color'),
    ),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 48, color: color),
          for (var i = 0; i < 3; i++)
            Row(
              children: [
                Text(const ['R', 'G', 'B'][i]),
                Expanded(
                  child: Slider(
                    value: channels[i],
                    onChanged: (value) => setState(() => channels[i] = value),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text('common.actions.cancel', 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, color),
        child: Text(widget.text('common.actions.confirm', 'Apply')),
      ),
    ],
  );
}
