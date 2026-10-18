import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A horizontal choice row with viewport paging and visible selection/focus.
class ScrollableChoiceChips<T extends Object> extends StatefulWidget {
  const ScrollableChoiceChips({
    super.key,
    required this.items,
    required this.value,
    required this.onSelected,
    required this.label,
    required this.previousLabel,
    required this.nextLabel,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onSelected;
  final String label, previousLabel, nextLabel;

  @override
  State<ScrollableChoiceChips<T>> createState() =>
      _ScrollableChoiceChipsState<T>();
}

class _ScrollableChoiceChipsState<T extends Object>
    extends State<ScrollableChoiceChips<T>> {
  final _scroll = ScrollController();
  final _row = GlobalKey();
  final _items = <T, GlobalKey>{};
  double _width = 0;
  bool _overflow = false, _atStart = true, _atEnd = true, _scheduled = false;
  T? _revealNext;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleMeasure);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overflow = false;
    _scheduleMeasure(reveal: widget.value);
  }

  @override
  void didUpdateWidget(covariant ScrollableChoiceChips<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedItems = !listEquals(widget.items, oldWidget.items);
    if (changedItems) _overflow = false;
    if (widget.value != oldWidget.value || changedItems) {
      _items.removeWhere(
        (key, _) => !widget.items.any((item) => item.$1 == key),
      );
      _scheduleMeasure(reveal: widget.value);
    }
  }

  void _scheduleMeasure({T? reveal}) {
    _revealNext = reveal ?? _revealNext;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final target = _revealNext;
      _revealNext = null;
      final row = _row.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.hasSize) return;
      // Measure the row before paging buttons narrow the viewport. Retain the
      // result until its items or available width change, so truncating a long
      // label cannot repeatedly hide and show the buttons.
      final overflow = _overflow || row.size.width > _width + 1;
      final position = _scroll.position;
      final atStart = position.pixels <= position.minScrollExtent + 1;
      final atEnd = position.pixels >= position.maxScrollExtent - 1;
      final resized = overflow != _overflow;
      if (resized || atStart != _atStart || atEnd != _atEnd) {
        setState(() {
          _overflow = overflow;
          _atStart = atStart;
          _atEnd = atEnd;
        });
      }
      if (target != null) {
        if (resized) {
          _scheduleMeasure(reveal: target);
        } else {
          _reveal(target);
        }
      }
    });
  }

  void _reveal(T value) {
    final item = _items[value]?.currentContext?.findRenderObject();
    if (item == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.of(item);
    final leading = viewport.getOffsetToReveal(item, 0).offset;
    final trailing = viewport.getOffsetToReveal(item, 1).offset;
    final position = _scroll.position;
    final offset = position.pixels
        .clamp(math.min(leading, trailing), math.max(leading, trailing))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((offset - position.pixels).abs() > .5) _scroll.jumpTo(offset);
  }

  void _page(int direction) {
    final position = _scroll.position;
    final offset =
        (position.pixels + direction * position.viewportDimension * .8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: Durations.short4,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width != constraints.maxWidth) {
        _width = constraints.maxWidth;
        _overflow = false;
        _scheduleMeasure(reveal: widget.value);
      }
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final content = NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _scheduleMeasure(reveal: widget.value);
          return false;
        },
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizeChangedLayoutNotifier(
              child: Row(
                key: _row,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (value, label) in widget.items)
                    Padding(
                      key: _items.putIfAbsent(value, GlobalKey.new),
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.max(0, viewport.maxWidth - 8),
                        ),
                        child: Focus(
                          canRequestFocus: false,
                          onFocusChange: (focused) {
                            if (focused) _scheduleMeasure(reveal: value);
                          },
                          child: Tooltip(
                            message: label,
                            child: ChoiceChip(
                              showCheckmark: false,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              visualDensity: VisualDensity.standard,
                              label: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: value == widget.value,
                              onSelected: (_) {
                                widget.onSelected(value);
                                _scheduleMeasure(reveal: value);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      Widget pageButton(bool previous) => IconButton(
        tooltip: previous ? widget.previousLabel : widget.nextLabel,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        visualDensity: VisualDensity.standard,
        icon: Icon(
          (previous != rtl)
              ? Symbols.chevron_left_rounded
              : Symbols.chevron_right_rounded,
        ),
        onPressed: (previous ? _atStart : _atEnd)
            ? null
            : () => _page(previous ? -1 : 1),
      );
      return Semantics(
        label: widget.label,
        container: true,
        child: constraints.hasBoundedWidth
            ? Row(
                children: [
                  if (_overflow) pageButton(true),
                  Expanded(child: content),
                  if (_overflow) pageButton(false),
                ],
              )
            : content,
      );
    },
  );
}
