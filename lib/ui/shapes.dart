import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import 'theme.dart';

/// Clips to a Material 3 Expressive shape morph (`--shape-*` in the website's
/// tokens) at [progress], scaled from the unit square to the child.
class MorphClipper extends CustomClipper<Path> {
  MorphClipper(this.morph, this.progress);
  final Morph morph;
  final double progress;

  @override
  Path getClip(Size size) => morph
      .toPath(progress: progress)
      .transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);

  @override
  bool shouldReclip(MorphClipper old) =>
      old.progress != progress || old.morph != morph;
}

final _squareToCookie = Morph(
  MaterialShapes.square.normalized(),
  MaterialShapes.cookie9Sided.normalized(),
);

/// The website's `.hub-link`: a 64 dp row on surface-container-low with an
/// icon in a secondary-container square that turns into a nine-sided cookie
/// and rotates while pressed or hovered, the label, and a count.
class HubLink extends StatefulWidget {
  const HubLink({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? count;
  final VoidCallback? onTap;

  @override
  State<HubLink> createState() => _HubLinkState();
}

class _HubLinkState extends State<HubLink> {
  bool _active = false;

  void _set(bool value) {
    if (value != _active) setState(() => _active = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: Durations.medium2,
      curve: Easing.emphasizedDecelerate,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(
          _active ? Corner.extraLarge : Corner.large,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _set,
          onHover: _set,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _active ? 1 : 0),
                    duration: Durations.medium2,
                    curve: Easing.emphasizedDecelerate,
                    builder: (context, t, _) => Transform.rotate(
                      angle: t * 0.349,
                      child: ClipPath(
                        clipper: MorphClipper(_squareToCookie, t),
                        child: Container(
                          width: 40,
                          height: 40,
                          color: scheme.secondaryContainer,
                          alignment: Alignment.center,
                          child: Transform.rotate(
                            angle: -t * 0.349,
                            child: Icon(
                              widget.icon,
                              size: 22,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (widget.count != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      widget.count!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips to one Material 3 Expressive shape, scaled to the child.
class PolygonClipper extends CustomClipper<Path> {
  PolygonClipper(this.shape);
  final RoundedPolygon shape;

  @override
  Path getClip(Size size) => shape.toPath().transform(
    Matrix4.diagonal3Values(size.width, size.height, 1).storage,
  );

  @override
  bool shouldReclip(PolygonClipper old) => old.shape != shape;
}

/// An icon on a shaped container (`.shape-*` in the website's styles).
class ShapedIcon extends StatelessWidget {
  const ShapedIcon({
    super.key,
    required this.shape,
    required this.child,
    this.size = 56,
    this.color,
    this.foreground,
  });
  final RoundedPolygon shape;
  final Widget child;
  final double size;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: PolygonClipper(shape),
      child: Container(
        width: size,
        height: size,
        color: color ?? scheme.secondaryContainer,
        alignment: Alignment.center,
        child: IconTheme.merge(
          data: IconThemeData(color: foreground ?? scheme.onSecondaryContainer),
          child: child,
        ),
      ),
    );
  }
}
