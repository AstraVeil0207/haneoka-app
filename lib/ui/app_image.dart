import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/net.dart';

const _localeImageTags = {
  'en': ['en'],
  'zh-TW': ['zh-Hant', 'zh-Hans'],
  'zh-CN': ['zh-Hans', 'zh-Hant'],
  'ko': ['ko'],
};
final _gameAsset = RegExp(r'/assets/[^/]+/(?:Assets|Packages)/');
final _tagged = RegExp(r'\((?:en|ko|zh-Hans|zh-Hant)\)(?=\.[^./]+$)');

/// Locale-tagged artwork candidates (`localeTaggedCandidates`): the reading
/// locale's variants, then the untagged original.
List<String> localeImageCandidates(String source, String locale) {
  final tags = _localeImageTags[locale];
  if (source.isEmpty ||
      tags == null ||
      !_gameAsset.hasMatch(source) ||
      _tagged.hasMatch(source)) {
    return [source];
  }
  final slash = source.lastIndexOf('/'), dot = source.lastIndexOf('.');
  return [
    for (final tag in tags)
      dot > slash
          ? '${source.substring(0, dot)}($tag)${source.substring(dot)}'
          : '$source($tag)',
    source,
  ];
}

/// Addresses that failed this session, so a missing variant is asked for once.
final _missing = <String>{};

/// Network artwork decoded at the size it is shown, trying each candidate in
/// turn (original first, thumbnail last), as the website's `nextImageCandidate`.
class AppImage extends StatefulWidget {
  const AppImage({
    super.key,
    required this.candidates,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.alignment = Alignment.center,
    this.localized = true,
  });
  final List<String> candidates;

  /// Whether each candidate is first tried in the reading locale's own
  /// artwork (`banner(zh-Hans).png` beside `banner.png`).
  final bool localized;
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
    final locale = widget.localized
        ? AppScope.maybeOf(context)?.text.locale
        : null;
    final candidates = [
      for (final source in widget.candidates)
        for (final url
            in locale == null
                ? [source]
                : localeImageCandidates(source, locale))
          if (!_missing.contains(url)) url,
    ];
    if (_index >= candidates.length) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth * ratio).round()
            : null;
        return CachedNetworkImage(
          key: ValueKey(candidates[_index]),
          imageUrl: candidates[_index],
          cacheManager: artworkCache,
          fit: widget.fit,
          alignment: widget.alignment,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: width,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => const SizedBox.expand(),
          errorWidget: (_, _, _) {
            final failed = candidates[_index];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Dropping the failed address moves the next candidate into place.
              _missing.add(failed);
              if (mounted) setState(() {});
            });
            return const SizedBox.expand();
          },
        );
      },
    );
  }
}
