import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum OverlayShape { rect, text, circle }

enum OverlayBinding {
  static,
  scoreA,
  scoreB,
  scoreVs,
  teamAName,
  teamBName,
  matchClock,
  periodLabel,
}

enum OverlayTextAlign { left, center, right }

enum OverlayFontWeight { normal, bold }

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

@immutable
class OverlayRect {
  const OverlayRect({
    required this.x1,
    required this.y1,
    required this.z,
    required this.x2,
    required this.y2,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final int z;
}

@immutable
class OverlayStyle {
  const OverlayStyle({
    this.fillColor,
    this.textColor,
    this.opacity = 1.0,
    this.cornerRadius = 0.0,
    this.fontFamily,
    this.fontSize = 24.0,
    this.textAlign = OverlayTextAlign.center,
    this.fontWeight = OverlayFontWeight.normal,
    this.staticText,
  });

  final String? fillColor;
  final String? textColor;
  final double opacity;
  final double cornerRadius;
  final String? fontFamily;
  final double fontSize;
  final OverlayTextAlign textAlign;
  final OverlayFontWeight fontWeight;
  final String? staticText;
}

@immutable
class OverlayElement {
  const OverlayElement({
    required this.id,
    required this.shape,
    required this.bounds,
    required this.style,
    required this.binding,
    this.visible = true,
  });

  final String id;
  final OverlayShape shape;
  final OverlayRect bounds;
  final OverlayStyle style;
  final OverlayBinding binding;
  final bool visible;
}

@immutable
class OverlayTemplate {
  const OverlayTemplate({
    required this.eventType,
    required this.durationMs,
    required this.elements,
  });

  final String eventType;
  final int durationMs;
  final List<OverlayElement> elements;
}

@immutable
class OverlayLayout {
  const OverlayLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.elements,
    required this.templates,
  });

  final int canvasWidth;
  final int canvasHeight;
  final List<OverlayElement> elements;
  final List<OverlayTemplate> templates;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// A broadcast-style "bug" scoreboard, top-left, authored at the firmware's
/// native 1280×720 output. Layout: [home color tab | home | score | away |
/// away color tab | clock·period cell]. The firmware renders this onto the
/// stream; the app no longer draws its own copy (A6a).
///
/// The rendered team names come from the `teamAName`/`teamBName` bindings (i.e.
/// `PushSessionConfigCommand.team_a_name`/`team_b_name`), NOT [homeName]/
/// [awayName] — those params are retained for call-site compatibility only.
/// [homeColorHex]/[awayColorHex] drive the end tabs.
OverlayLayout defaultScoreboardLayout({
  required String homeName,
  required String awayName,
  String? homeColorHex,
  String? awayColorHex,
}) {
  final homeColor = homeColorHex ?? '#9AA3B2';
  final awayColor = awayColorHex ?? '#9AA3B2';

  // Bug geometry on a 1280×720 canvas. Top-left (soccer standard), 52px tall.
  // x: 24 [tab8] 32 [home108] 140 [score132] 272 [away108] 380 [tab8] 388
  //    [clock cell 76] 464
  const top = 24.0;
  const bot = 76.0;

  // ---- Persistent elements (z>0; z=0 is the video itself) ----
  const bg = OverlayElement(
    id: 'bg',
    shape: OverlayShape.rect,
    bounds: OverlayRect(x1: 24, y1: top, x2: 464, y2: bot, z: 1),
    style: OverlayStyle(fillColor: '#14161A', opacity: 0.92, cornerRadius: 8),
    binding: OverlayBinding.static,
  );

  // Darker cell behind the clock/period at the right end.
  const clockCell = OverlayElement(
    id: 'clock_cell',
    shape: OverlayShape.rect,
    bounds: OverlayRect(x1: 388, y1: top, x2: 464, y2: bot, z: 2),
    style: OverlayStyle(fillColor: '#0E1014', opacity: 0.92),
    binding: OverlayBinding.static,
  );

  final homeTab = OverlayElement(
    id: 'home_tab',
    shape: OverlayShape.rect,
    bounds: const OverlayRect(x1: 24, y1: top, x2: 32, y2: bot, z: 2),
    style: OverlayStyle(fillColor: homeColor),
    binding: OverlayBinding.static,
  );

  final awayTab = OverlayElement(
    id: 'away_tab',
    shape: OverlayShape.rect,
    bounds: const OverlayRect(x1: 380, y1: top, x2: 388, y2: bot, z: 2),
    style: OverlayStyle(fillColor: awayColor),
    binding: OverlayBinding.static,
  );

  const homeNameElement = OverlayElement(
    id: 'home_name',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 42, y1: 32, x2: 140, y2: 68, z: 3),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.left,
      fontSize: 22,
      fontWeight: OverlayFontWeight.bold,
      fontFamily: 'Inter',
    ),
    binding: OverlayBinding.teamAName,
  );

  const score = OverlayElement(
    id: 'score',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 140, y1: 28, x2: 272, y2: 74, z: 3),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.center,
      fontSize: 26,
      fontWeight: OverlayFontWeight.bold,
      fontFamily: 'Inter',
    ),
    binding: OverlayBinding.scoreVs,
  );

  const awayNameElement = OverlayElement(
    id: 'away_name',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 274, y1: 32, x2: 378, y2: 68, z: 3),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.left,
      fontSize: 22,
      fontWeight: OverlayFontWeight.bold,
      fontFamily: 'Inter',
    ),
    binding: OverlayBinding.teamBName,
  );

  const clock = OverlayElement(
    id: 'clock',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 388, y1: 28, x2: 464, y2: 54, z: 3),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.center,
      fontSize: 17,
      fontWeight: OverlayFontWeight.bold,
      fontFamily: 'Inter',
    ),
    binding: OverlayBinding.matchClock,
  );

  const period = OverlayElement(
    id: 'period',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 388, y1: 54, x2: 464, y2: 74, z: 3),
    style: OverlayStyle(
      textColor: '#AEB6C4',
      textAlign: OverlayTextAlign.center,
      fontSize: 11,
      fontFamily: 'Inter',
    ),
    binding: OverlayBinding.periodLabel,
  );

  // ---- Banner templates — clean broadcast event cards ----
  final goalTemplate = _eventBanner(
    eventType: 'goal',
    durationMs: 5000,
    title: 'GOAL',
    accent: '#F5B301',
  );
  final yellowCardTemplate = _eventBanner(
    eventType: 'yellow_card',
    durationMs: 4000,
    title: 'YELLOW CARD',
    accent: '#FFC400',
  );
  final redCardTemplate = _eventBanner(
    eventType: 'red_card',
    durationMs: 4000,
    title: 'RED CARD',
    accent: '#E5484D',
  );
  final substitutionTemplate = _eventBanner(
    eventType: 'substitution',
    durationMs: 4000,
    title: 'SUBSTITUTION',
    accent: '#3DAE5A',
  );

  return OverlayLayout(
    canvasWidth: 1280,
    canvasHeight: 720,
    elements: [
      bg,
      clockCell,
      homeTab,
      awayTab,
      homeNameElement,
      score,
      awayNameElement,
      clock,
      period,
    ],
    templates: [
      goalTemplate,
      yellowCardTemplate,
      redCardTemplate,
      substitutionTemplate,
    ],
  );
}

/// A centred broadcast "event card": a dark rounded panel with a coloured
/// accent bar on the left, a bold [title], and a player subtitle that resolves
/// `{{player}}` (e.g. "#7", blank when no jersey). Replaces the old flat
/// coloured rectangle. Authored on the 1280×720 canvas.
OverlayTemplate _eventBanner({
  required String eventType,
  required int durationMs,
  required String title,
  required String accent,
}) {
  return OverlayTemplate(
    eventType: eventType,
    durationMs: durationMs,
    elements: [
      OverlayElement(
        id: '${eventType}_bg',
        shape: OverlayShape.rect,
        bounds: const OverlayRect(x1: 410, y1: 300, x2: 870, y2: 384, z: 10),
        style: const OverlayStyle(
          fillColor: '#14161A',
          opacity: 0.96,
          cornerRadius: 10,
        ),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: '${eventType}_accent',
        shape: OverlayShape.rect,
        bounds: const OverlayRect(x1: 410, y1: 300, x2: 422, y2: 384, z: 11),
        style: OverlayStyle(fillColor: accent),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: '${eventType}_title',
        shape: OverlayShape.text,
        bounds: const OverlayRect(x1: 444, y1: 312, x2: 858, y2: 352, z: 12),
        style: OverlayStyle(
          staticText: title,
          textColor: '#FFFFFF',
          fontSize: 30,
          fontWeight: OverlayFontWeight.bold,
          textAlign: OverlayTextAlign.left,
          fontFamily: 'Inter',
        ),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: '${eventType}_player',
        shape: OverlayShape.text,
        bounds: const OverlayRect(x1: 444, y1: 350, x2: 858, y2: 376, z: 12),
        style: const OverlayStyle(
          staticText: '{{player}}',
          textColor: '#AEB6C4',
          fontSize: 16,
          textAlign: OverlayTextAlign.left,
          fontFamily: 'Inter',
        ),
        binding: OverlayBinding.static,
      ),
    ],
  );
}
