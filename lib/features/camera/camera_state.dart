// Camera selection providers moved to core/state/camera_selection.dart —
// they are cross-feature state (consumed by core controllers/widgets and
// several features), which the layering convention places in core/state/.
// This shim keeps the historical import path working for feature code.

export '../../core/state/camera_selection.dart';
