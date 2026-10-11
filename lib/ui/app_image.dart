import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network artwork decoded at the size it is shown, trying each candidate in
/// turn (original first, thumbnail last), as the website's `nextImageCandidate`.
class AppImage extends StatefulWidget {
  const AppImage({
    super.key,
    required this.candidates,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.alignment = Alignment.center,
  });
  final List<String> candidates;
  final BoxFit fit;
  final Alignment alignment;

  /// Shown when no candidate loads.
  final Widget? placeholder;

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  int _index = 0;

  @override
  void didUpdateWidget(AppImage old) {
    super.didUpdateWidget(old);
    if (old.candidates.firstOrNull != widget.candidates.firstOrNull) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.candidates.length) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth * ratio).round()
            : null;
        return CachedNetworkImage(
          key: ValueKey(widget.candidates[_index]),
          imageUrl: widget.candidates[_index],
          fit: widget.fit,
          alignment: widget.alignment,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: width,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => const SizedBox.expand(),
          errorWidget: (_, _, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _index++);
            });
            return const SizedBox.expand();
          },
        );
      },
    );
  }
}
