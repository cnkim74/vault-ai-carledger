# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keep,includedescriptorclasses class com.cnkim74.wheelet.**$$serializer { *; }
-keepclassmembers class com.cnkim74.wheelet.** {
    *** Companion;
}
