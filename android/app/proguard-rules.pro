# Tell the compiler it is safe to completely ignore and delete the Play Core split framework
-dontwarn com.google.android.play.core.**

# Explicitly allow R8 to aggressively strip out the specific classes flagged by F-Droid
-assumenosideeffects class com.google.android.play.core.splitinstall.** { *; }
-assumenosideeffects class com.google.android.play.core.splitcompat.** { *; }
-assumenosideeffects class com.google.android.play.core.tasks.** { *; }