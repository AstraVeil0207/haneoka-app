import 'package:flutter/material.dart';

import 'app_image.dart';

enum GameCardKind { member, support }

class CardSkillMark {
  const CardSkillMark(this.icon, this.level, this.label);
  final String icon;
  final int? level;
  final String label;
}

class CardGrowthDisplay {
  const CardGrowthDisplay({
    required this.level,
    required this.rank,
    required this.rankIcon,
    required this.rankLabel,
    this.training,
    this.trainingIcon,
    this.trainingLabel = '',
    this.liveSkill,
    this.gekisoSkill,
    this.unknown = '?',
  });
  final int? level, rank, training;
  final String? rankIcon, trainingIcon;
  final String rankLabel, trainingLabel, unknown;
  final CardSkillMark? liveSkill, gekisoSkill;
}

/// The same artwork geometry serves catalogues, card boxes and formations.
class CardArtwork extends StatelessWidget {
  const CardArtwork({
    super.key,
    required this.kind,
    required this.image,
    this.attribute,
    this.attributeLabel,
    this.rarity,
    this.rarityLabel,
    this.growth,
  });
  final GameCardKind kind;
  final String image;
  final String? attribute, attributeLabel, rarity, rarityLabel;
  final CardGrowthDisplay? growth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth, height = constraints.maxHeight;
      final member = kind == GameCardKind.member;
      final markSize = width * (member ? 0.22321429 : 0.15337423);
      final values = growth;
      String value(int? n) => n?.toString() ?? values!.unknown;
      Widget number(String text, double size) => Stack(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.7
                ..color = Colors.black,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: const [Shadow(blurRadius: 2, offset: Offset(0, 1))],
            ),
          ),
        ],
      );
      Widget emblem(
        String url,
        double size,
        String? label, {
        bool natural = false,
      }) => Semantics(
        label: label,
        child: SizedBox(
          width: size,
          height: natural ? null : size,
          child: AppImage(
            candidates: [url],
            localized: false,
            naturalHeight: natural,
          ),
        ),
      );
      Widget skill(CardSkillMark skill, double size) => Tooltip(
        message: '${skill.label} ${value(skill.level)}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            emblem(skill.icon, size * 1.2, skill.label),
            SizedBox(width: size * 0.15),
            number(value(skill.level), size),
          ],
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          AppImage(candidates: [image], fit: BoxFit.cover),
          if (attribute case final url? when url.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              child: emblem(url, markSize, attributeLabel, natural: true),
            ),
          if (rarity case final url? when url.isNotEmpty)
            Positioned(
              top: 0,
              right: 0,
              child: emblem(url, markSize, rarityLabel, natural: true),
            ),
          if (values != null) ...[
            Positioned(
              left: width * 0.03,
              bottom: height * 0.03,
              child: number(
                'Lv.${value(values.level)}',
                (width * 0.14).clamp(9, 22),
              ),
            ),
            if (member)
              Positioned(
                left: width * 0.03,
                bottom: height * 0.15,
                child: Tooltip(
                  message: '${values.trainingLabel} ${value(values.training)}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (values.trainingIcon case final icon?
                          when icon.isNotEmpty)
                        emblem(
                          icon,
                          (width * 0.12).clamp(9, 18) * 0.95,
                          values.trainingLabel,
                        ),
                      SizedBox(width: width * 0.015),
                      number(
                        value(values.training),
                        (width * 0.12).clamp(9, 18),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: width * 0.03,
              bottom: height * 0.29,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: width * 0.044,
                children: [
                  for (final mark in [values.liveSkill, values.gekisoSkill])
                    if (mark != null && mark.icon.isNotEmpty)
                      skill(mark, (width * 0.11).clamp(9, 16)),
                ],
              ),
            ),
            if (values.rankIcon case final url? when url.isNotEmpty)
              Positioned(
                right: 0,
                bottom: 0,
                child: Tooltip(
                  message: '${values.rankLabel} ${value(values.rank)}',
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      emblem(
                        url,
                        width * (member ? 0.28571429 : 0.19631902),
                        values.rankLabel,
                        natural: true,
                      ),
                      if (values.rank == null)
                        number(values.unknown, (width * 0.14).clamp(9, 18)),
                    ],
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}
