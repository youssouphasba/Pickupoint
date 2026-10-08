import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let googleMapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
       !googleMapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      GMSServices.provideAPIKey(googleMapsApiKey)
    } else {
      NSLog("[Denkma] ERREUR FATALE: GoogleMapsApiKey est absente ou vide dans Info.plist. Toute page avec une carte va crasher. Vérifier la variable Codemagic GOOGLE_MAPS_IOS_KEY.")
    }

    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "DenkmaDriverLocationPermission") {
      DriverLocationPermissionBridge.register(with: registrar.messenger())
    } else {
      NSLog("[Denkma] Le canal d’autorisation de localisation du livreur n’a pas pu être enregistré.")
    }
    if let registrar = registrar(forPlugin: "DenkmaDriverMissionActivity") {
      DriverMissionActivityBridge.register(with: registrar.messenger())
    } else {
      NSLog("[Denkma] Le canal des activités en direct n’a pas pu être enregistré.")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
