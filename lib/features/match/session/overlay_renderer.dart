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
  String? _activeBannerTemplateId;
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
        _activeBannerTemplateId = null;
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
        _bannerTimer?.cancel();
        final template = widget.layout.templates
            .where((t) => t.eventType == templateId)
            .firstOrNull;
        if (template != null) {
          setState(() {
            _activeBannerTemplateId = templateId;
            _activeBannerParams = events.first.params;
          });
          _bannerTimer = Timer(Duration(milliseconds: template.durationMs), () {
            if (mounted) {
              setState(() {
                _activeBannerTemplateId = null;
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

        final persistentWidgets = widget.layout.elements
            .where((e) => e.visible)
            .map((e) => _buildPositioned(e, s))
            .toList();

        final bannerWidgets = _activeBannerTemplateId != null
            ? (widget.layout.templates
                      .where((t) => t.eventType == _activeBannerTemplateId)
                      .firstOrNull
                      ?.elements
                      .where((e) => e.visible)
                      .map((e) => _buildPositioned(e, s))
                      .toList() ??
                  <Widget>[])
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
              borderRadius: BorderRadius.circular(el.style.cornerRadius),
            ),
          ),
        );
      case OverlayShape.text:
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _resolveAlign(el.style.textAlign),
          child: Text(
            _resolveBinding(el.binding, el.style.staticText),
            style: TextStyle(
              color: _parseHex(el.style.textColor),
              fontSize: el.style.fontSize * s,
              fontWeight: el.style.fontWeight == OverlayFontWeight.bold
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontFamily: el.style.fontFamily,
            ),
          ),
        );
      case OverlayShape.circle:
        return Container(
          decoration: BoxDecoration(
            color: _parseHex(el.style.fillColor),
            shape: BoxShape.circle,
          ),
        );
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

  Alignment _resolveAlign(OverlayTextAlign align) {
    switch (align) {
      case OverlayTextAlign.left:
        return Alignment.centerLeft;
      case OverlayTextAlign.center:
        return Alignment.center;
      case OverlayTextAlign.right:
        return Alignment.centerRight;
    }
  }
}
