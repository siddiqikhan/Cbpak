# CBPAK

CBPAK is a Flutter Android app for coordinating local rides and small deliveries. It brings customers and drivers into one place, with vehicle choices and request tools designed around everyday transport needs in Pakistan.

## Why CBPAK

The goal of CBPAK is to make it easier for customers to request a ride or delivery and for drivers to find and manage those requests. The app combines common local transport options with clear request details, driver approval, location sharing, and fare estimates. It is intended to support more straightforward coordination between customers and drivers.

## What the app can do

### For customers

- Create an account and sign in with Firebase Authentication.
- Request rides and delivery services.
- Choose from available options such as car, bike, rickshaw, or courier by bike.
- Provide pickup and destination details, ride or delivery preferences, and other request information.
- View request status, cancel eligible open requests, and review ride history.
- Share or copy location details and contact a driver using supported phone and WhatsApp actions.

### For drivers and administrators

- Register a driver profile for review.
- Use the driver dashboard to see incoming requests and accept or decline them.
- View driver ride history and customer contact details for accepted requests.
- Review driver profiles and manage requests through the administrator dashboard.

Driver approval and access are governed by the included Cloud Firestore security rules. Review those rules and configure the required administrator account in your Firebase project before using the app with real users.

### Fare estimates and routing

The fare estimator requests a road route from the public OSRM demo service and calculates an estimate using configurable per-vehicle rates and minimum fares. It needs an internet connection. The estimate does not include live traffic, and the public demo service does not guarantee production uptime. Check that pickup and destination coordinates are correct before relying on an estimate.

## Technology

- Flutter and Dart for the Android app.
- Firebase Authentication for account sign-in.
- Cloud Firestore for driver profiles, ride requests, and ride contacts.
- OSRM routing with OpenStreetMap data for road-distance estimates.
- Android location permissions and external map/contact actions for location sharing.

## Project status

This repository contains the app source and Android project files. Firebase app configuration, signing credentials, generated build products, and other private local files are intentionally excluded. The app needs to be connected to the owner's Firebase project before authentication and Firestore-backed features can run.

## Getting started

Install Flutter and the Android development tools, then from the project directory run:

```powershell
flutter pub get
flutter run
```

### Connect Firebase

1. In Firebase Console, register an Android app with the application ID `com.example.cbpak` (from `android/app/build.gradle.kts`).
2. Enable the sign-in providers the app uses, including Email/Password and Google.
3. Configure Firebase for Flutter and Android. This creates local configuration such as `lib/firebase_options.dart` and `android/app/google-services.json`.
4. Set up Cloud Firestore, review `firestore.rules`, and configure administrator access for your project.
5. For Google sign-in, add the required SHA certificate fingerprints for the signing key you use.

Keep Firebase service-account keys, signing keys, and other credentials private. Do not commit them to this repository. The Git ignore rules exclude common local Firebase configuration and signing files.

## Repository contents

- `lib/` — Flutter application screens, dashboards, ride requests, location handling, and fare estimation.
- `android/` — Android app and build configuration.
- `firestore.rules` — Firestore access rules for the app's data.
- `pubspec.yaml` and `pubspec.lock` — Flutter dependencies.

## Notes

CBPAK is an evolving project. Fare rates, Firebase configuration, administrator access, and Firestore rules should be reviewed for the intended deployment before inviting real users.
