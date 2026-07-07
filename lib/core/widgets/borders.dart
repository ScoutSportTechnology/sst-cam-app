// Border → BoxDecoration convenience shared by feature pages that draw a
// single hairline rule on a Container (`const Border(top: BorderSide(...))
// .toBoxDecoration()`). Was copy-pasted as a private extension in half a
// dozen feature files; one core copy now.

import 'package:flutter/material.dart';

extension BorderToBoxDecoration on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
