# Branding artwork — drop files here, then generate

Required files (exact names):

1. `splash.png` — full-bleed portrait splash (your day/night dtRide art,
   ideally 1080x1920 PNG). Rider app uses the DAY version, driver app the
   NIGHT version.
2. `icon.png` — square 1024x1024 app icon (logo mark on navy, no transparency)
   for launcher icons + Android 12 splash.

Then run inside the app folder:

    dart run flutter_native_splash:create
    dart run flutter_launcher_icons

And rebuild the APK/AAB.
