# LiteRT-LM native code looks up Java/Kotlin API methods such as
# SamplerConfig.getTopK() through JNI. R8 can rename those accessors in release
# builds, which aborts generation with "JNI DETECTED ERROR: mid == null".
-keep class com.google.ai.edge.litertlm.** { *; }
-keepnames class com.google.ai.edge.litertlm.**
