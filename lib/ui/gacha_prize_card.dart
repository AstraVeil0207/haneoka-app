import 'dart:math';

import 'package:flutter/material.dart';

import 'app_image.dart';
import 'theme.dart';

class GachaPrizeCard extends StatelessWidget {
  const GachaPrizeCard({
    super.key,
    required this.label,
    required this.rarityValue,
    this.image,
    this.attribute,
    this.rarity,
    this.pickup = false,
    this.pickupCount = 0,
    this.count = 0,
    this.aspectRatio = 1,
    this.onTap,
  });
  final String label;
  final int rarityValue, count, pickupCount;
  final String? image, attribute, rarity;
  final bool pickup;
  final double aspectRatio;
  final VoidCallback? onTap;
  Widget _up(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(Corner.full),
      ),
      child: Text(
        pickupCount > 0 ? 'UP ×$pickupCount' : 'UP',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 11,
          height: 16 / 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Material(
            color: rarityValue == 4 || rarityValue == 20
                ? scheme.tertiaryContainer
                : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(Corner.medium),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mark = min(constraints.maxWidth * 0.24, 22.0);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (image != null && image!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: AppImage(candidates: [image!]),
                        ),
                      if (attribute != null)
                        Positioned(
                          left: 3,
                          top: 3,
                          width: mark,
                          height: mark,
                          child: AppImage(candidates: [attribute!]),
                        ),
                      if (rarity != null)
                        Positioned(
                          right: 3,
                          top: 3,
                          width: mark,
                          height: mark,
                          child: AppImage(candidates: [rarity!]),
                        ),
                      if (pickup)
                        Positioned(left: 3, bottom: 3, child: _up(context)),
                      if (count > 0)
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(Corner.full),
                            ),
                            child: Text(
                              '×$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                height: 16 / 11,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
