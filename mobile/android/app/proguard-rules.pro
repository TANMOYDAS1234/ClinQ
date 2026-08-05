# R8 keep rules for the release build.
#
# Without these, medicine reminders silently never fire. flutter_local_
# notifications persists its scheduled notifications as JSON via Gson, and Gson
# resolves the list type through a TypeToken. R8 strips generic signatures by
# default, so the TypeToken loses its type argument and every read or write of
# the store throws:
#
#   java.lang.IllegalStateException: TypeToken must be created with a type
#   argument: new TypeToken<...>() {}
#
# It only breaks in release, because debug builds are not minified — which is
# exactly why it went unnoticed.

# Gson needs the generic signatures and its annotations intact.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses, EnclosingMethod

# The notifications plugin and the model classes it serialises.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Gson's own reflection entry points.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-dontwarn sun.misc.**
