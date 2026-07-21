# ProGuard rules for TFLite, Hive, and Flutter native plugins

# TensorFlow Lite C/C++ JNI keeps
-keep class com.tflite.** { *; }
-keepclassmembers class com.tflite.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }

# Hive database adapters
-keep class hive.** { *; }
-keep class * extends hive.TypeAdapter { *; }
-keepclassmembers class * extends hive.TypeAdapter { *; }

# Flutter Native Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
