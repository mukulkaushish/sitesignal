# flutter_local_notifications registers broadcast receivers and services only
# through AndroidManifest.xml, so R8 can't see they're reachable from code.
# Without these keeps, release builds silently drop notification delivery.
-keep class com.dexterous.** { *; }
-keep class * extends android.app.Application { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }

# sqflite_common_ffi resolves the SQLite native library and its Dart FFI
# bindings dynamically; keep the plugin package intact under shrinking.
-keep class com.tekartik.sqflite.** { *; }
