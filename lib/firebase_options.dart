// Generated manually from the platform Firebase configs (the FlutterFire CLI
// requires a ruby `xcodeproj` gem this project does not install): values come
// from android/app/google-services.json and ios/Runner/GoogleService-Info.plist
// (project `maidkit-0x001`, project number 332533411625). The macOS app uses
// the same Apple app as iOS — both bundle ids are `dev.solsynth.maid`.
//
// DO NOT put secrets here: Firebase API keys are public client identifiers,
// not credentials.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // No web Firebase app is registered for MaidKit yet.
      throw UnsupportedError(
        'DefaultFirebaseOptions are not supported on this platform.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        // firebase_messaging has no Linux/Windows/fuchsia support; the app
        // never initializes Firebase there.
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported on this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC9hEQqRR-bwS5_tGnHBB8GxQTqQKI06gs',
    appId: '1:332533411625:android:baa94650006989571b1138',
    messagingSenderId: '332533411625',
    projectId: 'maidkit-0x001',
    storageBucket: 'maidkit-0x001.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAwB0k1hO7Iszr7se1BQ4ejAB_Hma5dwM0',
    appId: '1:332533411625:ios:59c6587a178988451b1138',
    messagingSenderId: '332533411625',
    projectId: 'maidkit-0x001',
    storageBucket: 'maidkit-0x001.firebasestorage.app',
    iosBundleId: 'dev.solsynth.maid',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAwB0k1hO7Iszr7se1BQ4ejAB_Hma5dwM0',
    appId: '1:332533411625:ios:59c6587a178988451b1138',
    messagingSenderId: '332533411625',
    projectId: 'maidkit-0x001',
    storageBucket: 'maidkit-0x001.firebasestorage.app',
    iosBundleId: 'dev.solsynth.maid',
  );
}
