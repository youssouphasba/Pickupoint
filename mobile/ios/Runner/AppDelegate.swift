import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Fournir la clé API Google Maps pour iOS (Ne pas builder avec la clé en dur sur git)
    let googleMapsApiKey = "VOTRE_CLE_IOS_ICI"
    GMSServices.provideAPIKey(googleMapsApiKey)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
