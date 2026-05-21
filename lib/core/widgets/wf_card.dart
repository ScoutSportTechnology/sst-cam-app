import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wireframe card — flat panel, hairline border, square corners.
class WfCard extends StatelessWidget {
  const WfCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? T.surface,
        border: Border.all(color: T.hair, width: 1),
      ),
      child: child,
    );
  }
}

/// Section header — small uppercase label with rule above the content.
class WfSection extends StatelessWidget {
  const WfSection(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 6),
  });

  final String label;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: T.ink2,
        ),
      ),
    );
  }
}

/// Tiny secondary text — used for meta info, hints.
class WfNote extends StatelessWidget {
  const WfNote(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, color: T.ink2).merge(style),
    );
  }
}

/// 16:9 striped placeholder used wherever the wireframe shows a video frame.
class ThumbPlaceholder extends StatelessWidget {
  const ThumbPlaceholder({super.key, this.label, this.height, this.aspect});

  final String? label;
  final double? height;
  final double? aspect;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: const BoxDecoration(
        color: T.fillSoft,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [T.fillSoft, T.fillMid, T.fillSoft],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _StripePainter(),
        child: Center(
          child: label == null || label!.isEmpty
              ? null
              : Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: T.mono,
                    color: T.ink3,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
    if (height != null) {
      return SizedBox(height: height, width: double.infinity, child: body);
    }
    return AspectRatio(aspectRatio: aspect ?? 16 / 9, child: body);
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    const step = 14.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
