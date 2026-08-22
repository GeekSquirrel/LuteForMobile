# Master rule for all Flutter plugins and Pigeon generated classes
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keepclassmembers class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
    public <init>(...);
}

# Keep GeneratedPluginRegistrant and all Flutter plugins
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keepclassmembers class io.flutter.plugins.GeneratedPluginRegistrant {
    public static void registerWith(...);
}

# Pigeon Generated APIs (used by shared_preferences_android, path_provider, etc.)
-dontwarn dev.flutter.pigeon.**
-keep class dev.flutter.pigeon.** { *; }

# Shared Preferences
-dontwarn io.flutter.plugins.sharedpreferences.**
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Path Provider
-dontwarn io.flutter.plugins.pathprovider.**
-keep class io.flutter.plugins.pathprovider.** { *; }

# Package Info Plus
-dontwarn dev.fluttercommunity.plus.packageinfo.**
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# Dynamic Color
-dontwarn io.material.plugins.dynamic_color.**
-keep class io.material.plugins.dynamic_color.** { *; }

# Flutter TTS
-dontwarn com.eyedeadevelopment.fluttertts.**
-keep class com.eyedeadevelopment.fluttertts.** { *; }

# Audioplayers
-dontwarn xyz.luan.audioplayers.**
-keep class xyz.luan.audioplayers.** { *; }

# File Picker
-dontwarn com.mr.flutter.plugin.filepicker.**
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Permission Handler
-dontwarn com.baseflow.permissionhandler.**
-keep class com.baseflow.permissionhandler.** { *; }

# URL Launcher
-dontwarn io.flutter.plugins.urllauncher.**
-keep class io.flutter.plugins.urllauncher.** { *; }

# Flutter InAppWebView
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }

# App Settings
-dontwarn com.example.app_settings.**
-dontwarn com.brianegan.app_settings.**
-dontwarn **.app_settings.**
-keep class **.app_settings.** { *; }

# Flutter Play Core Deferred Components
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Flutter Engine & Framework
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Hive / Hive CE
-keep class dev.hive_ce.** { *; }
-keep class hive_ce.** { *; }
-keep class ** extends dev.hive_ce.TypeAdapter { *; }
-keep class ** extends hive.TypeAdapter { *; }
-keep class ** extends io.realm.Transformer { *; }
-keepclassmembers class * {
    @hive.HiveField *;
}

# Riverpod & State Management
-keep class flutter_riverpod.** { *; }
-keep class riverpod.** { *; }

# Preserve custom data models
-keep class com.schlick7.luteformobile.** { *; }
