# Flutter Proguard Rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Preserve VLC player native bindings
-keep class org.videolan.libvlc.** { *; }
-dontwarn org.videolan.libvlc.**

# Preserve flutter_vlc_player classes (Pigeon interfaces, Messages class, etc.)
-keep class software.solid.fluttervlcplayer.** { *; }
-dontwarn software.solid.fluttervlcplayer.**

# Keep Play Core classes required by Flutter
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.**
