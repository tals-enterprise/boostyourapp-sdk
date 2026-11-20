# API publique du SDK, appelée par les apps et les plugins (Capacitor, Cordova, React Native)
-keep class com.boostyourapp.network.BoostNetwork { public *; }
-keep class com.boostyourapp.network.BoostEvent { *; }
-keep class com.boostyourapp.network.BoostEvent$* { *; }
-keep interface com.boostyourapp.network.BoostEventListener { *; }
-keep enum com.boostyourapp.network.BannerPosition { *; }
