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
    this.fontFamily = '',
    this.fontSize = 24.0,
    this.textAlign = OverlayTextAlign.center,
    this.fontWeight = OverlayFontWeight.normal,
    this.staticText,
  });

  final String? fillColor;
  final String? textColor;
  final double opacity;
  final double cornerRadius;
  final String fontFamily;
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

/// Returns a canonical 1920×1080 scoreboard layout with persistent elements
/// and four banner templates.
OverlayLayout defaultScoreboardLayout({
  required String homeName,
  required String awayName,
  String? homeColorHex,
  String? awayColorHex,
}) {
  final homeColor = homeColorHex ?? '#808080';
  final awayColor = awayColorHex ?? '#808080';

  // ---- Persistent elements ----
  const bg = OverlayElement(
    id: 'bg',
    shape: OverlayShape.rect,
    bounds: OverlayRect(x1: 0, y1: 950, x2: 1920, y2: 1080, z: 0),
    style: OverlayStyle(fillColor: '#111111', opacity: 0.85),
    binding: OverlayBinding.static,
  );

  final homeNameElement = OverlayElement(
    id: 'home_name',
    shape: OverlayShape.text,
    bounds: const OverlayRect(x1: 20, y1: 970, x2: 600, y2: 1040, z: 1),
    style: OverlayStyle(
      textColor: homeColor,
      textAlign: OverlayTextAlign.left,
      fontSize: 36,
      fontWeight: OverlayFontWeight.bold,
    ),
    binding: OverlayBinding.teamAName,
  );

  final awayNameElement = OverlayElement(
    id: 'away_name',
    shape: OverlayShape.text,
    bounds: const OverlayRect(x1: 1320, y1: 970, x2: 1900, y2: 1040, z: 1),
    style: OverlayStyle(
      textColor: awayColor,
      textAlign: OverlayTextAlign.right,
      fontSize: 36,
      fontWeight: OverlayFontWeight.bold,
    ),
    binding: OverlayBinding.teamBName,
  );

  const score = OverlayElement(
    id: 'score',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 760, y1: 960, x2: 1160, y2: 1050, z: 1),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.center,
      fontSize: 48,
      fontWeight: OverlayFontWeight.bold,
    ),
    binding: OverlayBinding.scoreVs,
  );

  const period = OverlayElement(
    id: 'period',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 800, y1: 1040, x2: 1120, y2: 1075, z: 1),
    style: OverlayStyle(
      textColor: '#AAAAAA',
      textAlign: OverlayTextAlign.center,
      fontSize: 24,
    ),
    binding: OverlayBinding.periodLabel,
  );

  const clock = OverlayElement(
    id: 'clock',
    shape: OverlayShape.text,
    bounds: OverlayRect(x1: 680, y1: 955, x2: 880, y2: 990, z: 1),
    style: OverlayStyle(
      textColor: '#FFFFFF',
      textAlign: OverlayTextAlign.center,
      fontSize: 30,
    ),
    binding: OverlayBinding.matchClock,
  );

  // ---- Banner templates ----
  const goalTemplate = OverlayTemplate(
    eventType: 'goal',
    durationMs: 5000,
    elements: [
      OverlayElement(
        id: 'goal_banner',
        shape: OverlayShape.rect,
        bounds: OverlayRect(x1: 560, y1: 400, x2: 1360, y2: 550, z: 10),
        style: OverlayStyle(fillColor: '#FFD700', opacity: 0.9),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: 'goal_text',
        shape: OverlayShape.text,
        bounds: OverlayRect(x1: 560, y1: 400, x2: 1360, y2: 550, z: 10),
        style: OverlayStyle(
          staticText: 'GOAL!',
          textColor: '#000000',
          fontSize: 72,
          fontWeight: OverlayFontWeight.bold,
          textAlign: OverlayTextAlign.center,
        ),
        binding: OverlayBinding.static,
      ),
    ],
  );

  const yellowCardTemplate = OverlayTemplate(
    eventType: 'yellow_card',
    durationMs: 4000,
    elements: [
      OverlayElement(
        id: 'ycard_banner',
        shape: OverlayShape.rect,
        bounds: OverlayRect(x1: 700, y1: 420, x2: 1220, y2: 540, z: 10),
        style: OverlayStyle(fillColor: '#FFEB3B', opacity: 0.9),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: 'ycard_text',
        shape: OverlayShape.text,
        bounds: OverlayRect(x1: 700, y1: 420, x2: 1220, y2: 540, z: 10),
        style: OverlayStyle(
          staticText: 'YELLOW CARD',
          textColor: '#000000',
          fontSize: 48,
          fontWeight: OverlayFontWeight.bold,
          textAlign: OverlayTextAlign.center,
        ),
        binding: OverlayBinding.static,
      ),
    ],
  );

  const redCardTemplate = OverlayTemplate(
    eventType: 'red_card',
    durationMs: 4000,
    elements: [
      OverlayElement(
        id: 'rcard_banner',
        shape: OverlayShape.rect,
        bounds: OverlayRect(x1: 700, y1: 420, x2: 1220, y2: 540, z: 10),
        style: OverlayStyle(fillColor: '#F44336', opacity: 0.9),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: 'rcard_text',
        shape: OverlayShape.text,
        bounds: OverlayRect(x1: 700, y1: 420, x2: 1220, y2: 540, z: 10),
        style: OverlayStyle(
          staticText: 'RED CARD',
          textColor: '#FFFFFF',
          fontSize: 48,
          fontWeight: OverlayFontWeight.bold,
          textAlign: OverlayTextAlign.center,
        ),
        binding: OverlayBinding.static,
      ),
    ],
  );

  const substitutionTemplate = OverlayTemplate(
    eventType: 'substitution',
    durationMs: 4000,
    elements: [
      OverlayElement(
        id: 'sub_banner',
        shape: OverlayShape.rect,
        bounds: OverlayRect(x1: 640, y1: 420, x2: 1280, y2: 540, z: 10),
        style: OverlayStyle(fillColor: '#4CAF50', opacity: 0.9),
        binding: OverlayBinding.static,
      ),
      OverlayElement(
        id: 'sub_text',
        shape: OverlayShape.text,
        bounds: OverlayRect(x1: 640, y1: 420, x2: 1280, y2: 540, z: 10),
        style: OverlayStyle(
          staticText: 'SUBSTITUTION',
          textColor: '#FFFFFF',
          fontSize: 48,
          fontWeight: OverlayFontWeight.bold,
          textAlign: OverlayTextAlign.center,
        ),
        binding: OverlayBinding.static,
      ),
    ],
  );

  return OverlayLayout(
    canvasWidth: 1920,
    canvasHeight: 1080,
    elements: [bg, homeNameElement, awayNameElement, score, period, clock],
    templates: [
      goalTemplate,
      yellowCardTemplate,
      redCardTemplate,
      substitutionTemplate,
    ],
  );
}
