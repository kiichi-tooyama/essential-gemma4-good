import AppGroupSupport
import EssentialKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Task {
      await configureEssentialKit()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configureEssentialKit() async {
    let appGroupIdentifier =
      Bundle.main.object(forInfoDictionaryKey: "EssentialAppGroupIdentifier") as? String

    do {
      try await EssentialClient.initialize(
        EssentialConfiguration(
          appGroupIdentifier: appGroupIdentifier
        )
      )
      try synchronizeFlutterInstallations(appGroupIdentifier: appGroupIdentifier)
    } catch {
      NSLog("EssentialKit initialization failed: \(error.localizedDescription)")
    }
  }

  private func synchronizeFlutterInstallations(appGroupIdentifier: String?) throws {
    let supportURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let metadataURL = supportURL
      .appendingPathComponent("essential_models", isDirectory: true)
      .appendingPathComponent("metadata.json")

    let modelRegistry = try AppGroupModelRegistry(
      configuration: AppGroupConfiguration(groupIdentifier: appGroupIdentifier)
    )
    _ = try modelRegistry.synchronizeFlutterInstallations(metadataURL: metadataURL)
  }
}
