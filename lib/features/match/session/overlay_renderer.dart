import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/overlay_layout.dart';
import 'session_state.dart';

/// Renders an [OverlayLayout] onto a scaled surface, substituting live match bindings and showing timed banner overlays on events.
class OverlayLayoutRenderer extends StatefulWidget {
  const OverlayLayoutRenderer({
    super.key,
    required this.layout,
    required this.matchState,
  });

  final OverlayLayout layout;
  final LiveMatchState matchState;

  @override
  State<OverlayLayoutRenderer> createState() => _OverlayLayoutRendererState();
}

class _OverlayLayoutRendererState extends State<OverlayLayoutRenderer> {
  OverlayTemplate? _activeBannerTemplate;
  Map<String, String> _activeBannerParams = const {};
  Timer? _bannerTimer;
  int _lastEventCount = 0;

  static const _labelToTemplateId = {
    'Goal': 'goal',
    'Yellow Card': 'yellow_card',
    'Red Card': 'red_card',
    'Sub': 'substitution',
  };

  @override
  void initState() {
    super.initState();
    _lastEventCount = widget.matchState.events.length;
  }

  @override
  void didUpdateWidget(OverlayLayoutRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = widget.matchState.events;
    if (events.length < _lastEventCount) {
      // Event list shrank (e.g. LiveMatchController.reset()) — cancel any active banner.
      _bannerTimer?.cancel();
      setState(() {
        _activeBannerTemplate = null;
        _activeBannerParams = const {};
      });
      _lastEventCount = 0;
      return;
    }
    if (events.length > _lastEventCount) {
      final label = events.first.label;
      final labelPrefix = label.split(' · ').first;
      final templateId = _labelToTemplateId[labelPrefix];
      if (templateId != null) {
        final template = widget.layout.templates
            .where((t) => t.eventType == templateId)
            .firstOrNull;
        if (template != null) {
          _bannerTimer?.cancel();
          setState(() {
            _activeBannerTemplate = template;
            _activeBannerParams = events.first.params;
          });
          _bannerTimer = Timer(Duration(milliseconds: template.durationMs), () {
            if (mounted) {
              setState(() {
                _activeBannerTemplate = null;
                _activeBannerParams = const {};
              });
            }
          });
        }
      }
    }
    _lastEventCount = events.length;
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final s = math.min(
          constraints.maxWidth / widget.layout.canvasWidth,
          constraints.maxHeight / widget.layout.canvasHeight,
        );

        final persistentWidgets = (widget.layout.elements
                .where((e) => e.visible)
                .toList()
              ..sort((a, b) => a.bounds.z.compareTo(b.bounds.z)))
            .map((e) => _buildPositioned(e, s))
            .toList();

        final bannerWidgets = _activeBannerTemplate != null
            ? ((_activeBannerTemplate!.elements
                      .where((e) => e.visible)
                      .toList()
                    ..sort((a, b) => a.bounds.z.compareTo(b.bounds.z)))
                  .map((e) => _buildPositioned(e, s))
                  .toList())
            : <Widget>[];

        return Stack(children: [...persistentWidgets, ...bannerWidgets]);
      },
    );
  }

  Widget _buildPositioned(OverlayElement el, double s) {
    return Positioned(
      left: el.bounds.x1 * s,
      top: el.bounds.y1 * s,
      width: (el.bounds.x2 - el.bounds.x1) * s,
      height: (el.bounds.y2 - el.bounds.y1) * s,
      child: _buildElement(el, s),
    );
  }

  Widget _buildElement(OverlayElement el, double s) {
    switch (el.shape) {
      case OverlayShape.rect:
        return Opacity(
          opacity: el.style.opacity,
          child: Container(
            decoration: BoxDecoration(
              color: _parseHex(el.style.fillColor),
              borderRadius: BorderRadius.circular(
                _clampCornerRadius(el) * s,
              ),
            ),
          ),
        );
      case OverlayShape.text:
        // Spec (overlay-rendering.md §Text): word-wrap at bounds width,
        // top-aligned vertically, clipped to bounds height. No shrink-to-fit.
        // The Positioned parent gives this child a tight bounds-sized box, so
        // the Text wraps at the bounds width and lays out from the top.
        //
        // §Shapes: a non-empty fill_color on a TEXT element MUST paint the
        // bounds as a background box behind the glyphs (text_color paints the
        // glyphs). The fill sits inside the same Opacity so the element's alpha
        // multiplies fill + text together (per §Color & opacity).
        final textColor = _parseHex(el.style.textColor);
        final fillColor = _parseHex(el.style.fillColor);
        final hasFill = fillColor != Colors.transparent;
        final text = Text(
          _resolveBinding(el.binding, el.style.staticText),
          textAlign: _resolveTextAlign(el.style.textAlign),
          softWrap: true,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: textColor,
            fontSize: el.style.fontSize * s,
            height: 1.0, // natural single line height; no extra leading.
            fontWeight: el.style.fontWeight == OverlayFontWeight.bold
                ? FontWeight.bold
                : FontWeight.normal,
            fontFamily: _resolveFontFamily(el.style.fontFamily),
          ),
        );
        return Opacity(
          opacity: el.style.opacity,
          child: ClipRect(
            child: hasFill
                ? DecoratedBox(
                    decoration: BoxDecoration(color: fillColor),
                    // Fill the full bounds box; the text aligns within it.
                    child: SizedBox.expand(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: text,
                      ),
                    ),
                  )
                : text,
          ),
        );
      case OverlayShape.circle:
        return Opacity(
          opacity: el.style.opacity,
          child: CustomPaint(
            painter: _OvalPainter(_parseHex(el.style.fillColor)),
          ),
        );
    }
  }

  /// Clamps `corner_radius` to half the smaller side of `bounds`
  /// (overlay-rendering.md §Color & opacity — capsule/circle limit). Returned
  /// in canvas pixels; the caller scales it by [s].
  double _clampCornerRadius(OverlayElement el) {
    final w = (el.bounds.x2 - el.bounds.x1).abs();
    final h = (el.bounds.y2 - el.bounds.y1).abs();
    final maxRadius = math.min(w, h) / 2;
    return el.style.cornerRadius.clamp(0.0, maxRadius);
  }

  /// Maps the contract's logical font families to a metrically-comparable
  /// face available to Flutter, so the preview stays within tolerance of the
  /// firmware's Pango rendering (overlay-rendering.md §Text). Non-logical
  /// families pass through unchanged (best-effort); null stays null.
  String? _resolveFontFamily(String? family) {
    switch (family) {
      case 'monospace':
        return 'monospace';
      case 'sans-serif':
        return 'sans-serif';
      case 'serif':
        return 'serif';
      default:
        return family;
    }
  }

  String _resolveBinding(OverlayBinding binding, String? staticText) {
    final s = widget.matchState;
    switch (binding) {
      case OverlayBinding.static:
        var text = staticText ?? '';
        for (final entry in _activeBannerParams.entries) {
          text = text.replaceAll('{{${entry.key}}}', entry.value);
        }
        text = text.replaceAll(RegExp(r'\{\{[^}]+\}\}'), '');
        return text;
      case OverlayBinding.scoreA:
        return '${s.scoreHome}';
      case OverlayBinding.scoreB:
        return '${s.scoreAway}';
      case OverlayBinding.scoreVs:
        return '${s.scoreHome} – ${s.scoreAway}';
      case OverlayBinding.teamAName:
        return s.homeName;
      case OverlayBinding.teamBName:
        return s.awayName;
      case OverlayBinding.matchClock:
        return s.clockText;
      case OverlayBinding.periodLabel:
        return s.periodLabelForOverlay;
    }
  }

  Color _parseHex(String? hex) {
    if (hex == null) return Colors.transparent;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return Colors.transparent;
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value == null) return Colors.transparent;
    return Color(value);
  }

  TextAlign _resolveTextAlign(OverlayTextAlign align) {
    switch (align) {
      case OverlayTextAlign.left:
        return TextAlign.left;
      case OverlayTextAlign.center:
        return TextAlign.center;
      case OverlayTextAlign.right:
        return TextAlign.right;
    }
  }
}

// Draws an ellipse inscribed in the full paint bounds, matching the spec's
// definition of SHAPE_CIRCLE ("ellipse inscribed in bounds").
class _OvalPainter extends CustomPainter {
  const _OvalPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Offset.zero & size,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OvalPainter old) => old.color != color;
}
