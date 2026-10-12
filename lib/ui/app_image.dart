import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/net.dart';
import '../core/storage.dart';

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
      _tagged.hasMatch(Uri.parse(source).path)) {
    return [source];
  }
  final uri = Uri.parse(source);
  final path = uri.path;
  final slash = path.lastIndexOf('/'), dot = path.lastIndexOf('.');
  return [
    for (final tag in tags)
      dot > slash
          ? uri
                .replace(
                  path: '${path.substring(0, dot)}($tag)${path.substring(dot)}',
                )
                .toString()
          : uri.replace(path: '$path($tag)').toString(),
    source,
  ];
}

/// Addresses that failed this session, so a missing variant is asked for once.
final _missing = <String>{};
final _retryAfter = <String, DateTime>{};

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
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppImage old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.candidates, widget.candidates)) _index = 0;
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
          if (!_missing.contains(url) &&
              !(_retryAfter[url]?.isAfter(DateTime.now()) ?? false))
            url,
    ];
    if (_index >= candidates.length) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    final url = candidates[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth * ratio).round().clamp(1, 8192)
            : null;
        return CachedNetworkImage(
          key: ValueKey(url),
          imageUrl: url,
          imageBuilder: (context, provider) {
            CacheStorage.instance.scheduleTrim();
            return Image(
              image: ResizeImage.resizeIfNeeded(width, null, provider),
              fit: widget.fit,
              alignment: widget.alignment,
              width: double.infinity,
              height: double.infinity,
            );
          },
          cacheManager: artworkCache,
          fit: widget.fit,
          alignment: widget.alignment,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: width,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => const SizedBox.expand(),
          errorWidget: (_, _, error) {
            final failed = url;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (error is HttpExceptionWithStatus &&
                  const {404, 410}.contains(error.statusCode)) {
                _missing.add(failed);
              } else {
                // Temporary network/decode failures can recover in this session.
                _retryAfter[failed] = DateTime.now().add(
                  const Duration(seconds: 30),
                );
                if (mounted) {
                  _retry ??= Timer(const Duration(seconds: 31), () {
                    _retry = null;
                    if (mounted) setState(() => _index = 0);
                  });
                }
              }
              if (mounted) setState(() {});
            });
            return const SizedBox.expand();
          },
        );
      },
    );
  }
}
