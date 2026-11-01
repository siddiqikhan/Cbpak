# CBPAK

Flutter Android app scaffold with an email/password login screen, account creation, password reset, and Google sign-in flow.

## Run

```powershell
flutter run
```

## Finish authentication setup

The UI and Firebase Auth calls are in place. Sign-in becomes active after connecting the app to a Firebase project:

1. Register the Android app in Firebase using the application ID shown in `android/app/build.gradle.kts`.
2. Enable Email/Password and Google under Firebase Authentication sign-in providers.
3. Add the Android SHA-1 fingerprint for the debug signing key.
4. Run FlutterFire configuration so the Android Google services file and Firebase options are generated.

Until Firebase configuration is added, the app displays the login screen with a setup notice and keeps the auth buttons from failing silently.
