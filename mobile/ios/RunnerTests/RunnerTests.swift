import CoreLocation
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private var manager: TestLocationManager!
  private var notifications: NotificationCenter!
  private var preferences: UserDefaults!
  private var preferencesName: String!
  private var applicationState: UIApplication.State = .active
  private var bridge: DriverLocationPermissionBridge!

  override func setUp() {
    super.setUp()
    manager = TestLocationManager()
    notifications = NotificationCenter()
    preferencesName = "DenkmaDriverLocationTests.\(UUID().uuidString)"
    preferences = UserDefaults(suiteName: preferencesName)
    applicationState = .active
    bridge = DriverLocationPermissionBridge(
      manager: manager, preferences: preferences, notifications: notifications,
      applicationState: { [unowned self] in self.applicationState }
    )
  }

  override func tearDown() {
    bridge = nil
    preferences.removePersistentDomain(forName: preferencesName)
    preferences = nil
    notifications = nil
    manager = nil
    super.tearDown()
  }

  func testExistingAlwaysPermissionDoesNotPrompt() {
    manager.status = .authorizedAlways
    var granted: Bool?
    bridge.requestAlways { granted = $0 as? Bool }
    XCTAssertEqual(granted, true)
    XCTAssertEqual(manager.requests, 0)
  }

  func testWhenInUseRequestsNativeUpgradeAndWaitsForApproval() {
    var granted: Bool?
    bridge.requestAlways { granted = $0 as? Bool }
    XCTAssertEqual(manager.requests, 1)
    XCTAssertNil(granted)
    resignActive()
    manager.status = .authorizedAlways
    bridge.locationManagerDidChangeAuthorization(manager)
    XCTAssertNil(granted)
    becomeActive()
    XCTAssertEqual(granted, true)
  }

  func testKeepingWhenInUseCompletesWithoutAnAuthorizationCallback() {
    var granted: Bool?
    bridge.requestAlways { granted = $0 as? Bool }
    resignActive()
    becomeActive()
    XCTAssertEqual(granted, false)
    XCTAssertTrue(preferences.bool(forKey: DriverLocationPermissionBridge.upgradePromptKey))
    bridge.requestAlways { granted = $0 as? Bool }
    XCTAssertEqual(granted, false)
    XCTAssertEqual(manager.requests, 1)
  }

  func testIgnoredRequestCompletesWithoutConsumingTheFuturePrompt() {
    let completed = expectation(description: "Ignored Always upgrade returns")
    bridge.requestAlways {
      XCTAssertEqual($0 as? Bool, false)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 4)
    XCTAssertFalse(preferences.bool(forKey: DriverLocationPermissionBridge.upgradePromptKey))
  }

  func testInitialInactiveStateDefersTheUpgradeUntilForeground() {
    applicationState = .inactive
    var granted: Bool?
    bridge.requestAlways { granted = $0 as? Bool }
    XCTAssertEqual(manager.requests, 0)
    XCTAssertNil(granted)
    becomeActive()
    XCTAssertEqual(manager.requests, 1)
    resignActive()
    becomeActive()
    XCTAssertEqual(granted, false)
  }

  func testConcurrentRequestsProduceOnePromptAndCompleteTogether() {
    var decisions: [Bool] = []
    for _ in 0..<2 {
      bridge.requestAlways { decisions.append($0 as! Bool) }
    }
    XCTAssertEqual(manager.requests, 1)
    resignActive()
    manager.status = .authorizedAlways
    becomeActive()
    XCTAssertEqual(decisions, [true, true])
  }

  func testDeniedRestrictedAndUndeterminedPermissionsNeverRequestAlways() {
    for status in [CLAuthorizationStatus.denied, .restricted, .notDetermined] {
      manager.status = status
      var granted: Bool?
      bridge.requestAlways { granted = $0 as? Bool }
      XCTAssertEqual(granted, false)
    }
    XCTAssertEqual(manager.requests, 0)
  }

  func testPrivacyResetRestoresTheNativeUpgradeOpportunity() {
    preferences.set(true, forKey: DriverLocationPermissionBridge.upgradePromptKey)
    manager.status = .notDetermined
    bridge.locationManagerDidChangeAuthorization(manager)
    manager.status = .authorizedWhenInUse
    bridge.requestAlways { _ in }
    XCTAssertEqual(manager.requests, 1)
  }

  private func resignActive() {
    applicationState = .inactive
    notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
  }

  private func becomeActive() {
    applicationState = .active
    notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
  }
}

private final class TestLocationManager: CLLocationManager {
  var status: CLAuthorizationStatus = .authorizedWhenInUse
  var requests = 0

  override var authorizationStatus: CLAuthorizationStatus { status }

  override func requestAlwaysAuthorization() {
    requests += 1
  }
}
