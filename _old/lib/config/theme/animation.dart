import 'package:flutter/material.dart';

final class Anim {
  Anim._();
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);

  static const curveIn = Curves.easeIn;
  static const curveOut = Curves.easeOut;
}
