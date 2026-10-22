import 'package:flutter/material.dart';

class GainColors {
  static const profit = Color(0xFFC62828);
  static const loss = Color(0xFF1B7A3A);
  static const flat = Color(0xFF5C6B73);

  static Color of(double value) {
    if (value > 0.004) return profit;
    if (value < -0.004) return loss;
    return flat;
  }
}
