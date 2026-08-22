import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

class DisplayModeService {
  /// Sets high refresh rate mode on Android devices (90Hz, 120Hz, 144Hz, etc.).
  /// On iOS, high refresh rate (ProMotion 120Hz) is enabled via CADisableMinimumFrameDurationOnPhone in Info.plist.
  static Future<void> applyDisplayMode({bool enableHighRefreshRate = true}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (enableHighRefreshRate) {
        final List<DisplayMode> modes = await FlutterDisplayMode.supported;
        if (modes.isNotEmpty) {
          final maxMode = modes.reduce(
            (a, b) => a.refreshRate > b.refreshRate ? a : b,
          );
          await FlutterDisplayMode.setPreferredMode(maxMode);
          debugPrint('DisplayModeService: Set preferred display mode to ${maxMode.width}x${maxMode.height}@${maxMode.refreshRate}Hz');
        } else {
          await FlutterDisplayMode.setHighRefreshRate();
        }
      } else {
        await FlutterDisplayMode.setLowRefreshRate();
      }
    } catch (e) {
      debugPrint('DisplayModeService: Error applying display mode: $e');
    }
  }
}
