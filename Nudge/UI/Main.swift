//
//  Main.swift
//  Nudge
//
//  Created by Erik Gomez on 2/2/21.
//

import UserNotifications
import SwiftUI
let windowDelegate = AppDelegate.WindowDelegate()
let dnc = DistributedNotificationCenter.default()
let nc = NotificationCenter.default
let snc = NSWorkspace.shared.notificationCenter

// Create an AppDelegate so that we can more finely control how Nudge operates
class AppDelegate: NSObject, NSApplicationDelegate {
    // This allows Nudge to terminate if all of the windows have been closed. It was needed when the close button was visible, but less needed now.
    // However if someone does close all the windows, we still want this.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillResignActive(_ notification: Notification) {
        // TODO: This function can be used to stop nudge from resigning its activation state
        // print("applicationWillResignActive")
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        // TODO: This function can be used to force nudge right back in front if a user moves to another app
        // print("applicationDidResignActive")
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        // TODO: Perhaps move some of the ContentView logic into this - Ex: updateUI()
        // print("applicationWillBecomeActive")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // TODO: Perhaps move some of the ContentView logic into this - Ex: centering UI, full screen
        // print("applicationDidBecomeActive")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // print("applicationDidFinishLaunching")
        if !nudgeLogState.afterFirstLaunch {
            nudgeLogState.afterFirstLaunch = true
            if NSWorkspace.shared.isActiveSpaceFullScreen() {
                NSApp.hide(self)
                // NSApp.windows.first?.resignKey()
                // NSApp.unhideWithoutActivation()
                // NSApp.deactivate()
                // NSApp.unhideAllApplications(nil)
                // NSApp.hideOtherApplications(self)
            }
        }
        
        // Observe all notifications generated by the default NotificationCenter
//        nc.addObserver(forName: nil, object: nil, queue: nil) { notification in
//            print("NotificationCenter: \(notification.name.rawValue), Object: \(notification)")
//        }
//        // Observe all notifications generated by the default DistributedNotificationCenter - No longer works as of Catalina
//        dnc.addObserver(forName: nil, object: nil, queue: nil) { notification in
//            print("DistributedNotificationCenter: \(notification.name.rawValue), Object: \(notification)")
//        }

        // Observe screen locking. Maybe useful later
        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { notification in
            utilsLog.info("\("Screen was locked", privacy: .public)")
        }

        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { notification in
            utilsLog.info("\("Screen was unlocked", privacy: .public)")
        }
        
        snc.addObserver(
            self,
            selector: #selector(logHiddenApplication(_:)),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )

        
        if attemptToBlockApplicationLaunches {
            registerLocal()
            snc.addObserver(
                self,
                selector: #selector(terminateApplication(_:)),
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )
        }

        // Listen for keyboard events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            if self.detectBannedShortcutKeys(with: $0) {
                return nil
            } else {
                return $0
            }
        }
    }
    
    @objc func logHiddenApplication(_ notification: Notification) {
        utilsLog.info("\("Application hidden", privacy: .public)")
    }
    
    @objc func terminateApplication(_ notification: Notification) {
        if !Utils().pastRequiredInstallationDate() {
            return
        }
        utilsLog.info("\("Application launched", privacy: .public)")
        for runningApplication in NSWorkspace.shared.runningApplications {
            let appBundleID = runningApplication.bundleIdentifier ?? ""
            let appName = runningApplication.localizedName ?? ""
            if appBundleID == "com.github.macadmins.Nudge" {
                continue
            }
            if blockedApplicationBundleIDs.contains(appBundleID) {
                utilsLog.info("\("Found \(appName), terminating application", privacy: .public)")
                scheduleLocal(applicationIdentifier: appName)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001, execute: {
                    runningApplication.forceTerminate()
                })
            }
        }
    }
    
    @objc func registerLocal() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .provisional, .sound]) { (granted, error) in
            if granted {
                uiLog.info("\("User granted notifications - application blocking status now available", privacy: .public)")
            } else {
                uiLog.info("\("User denied notifications - application blocking status will be unavailable", privacy: .public)")
            }
        }
    }

    @objc func scheduleLocal(applicationIdentifier: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { (settings) in
            let content = UNMutableNotificationContent()
            content.title = "Application terminated".localized(desiredLanguage: getDesiredLanguage())
            content.subtitle = "(\(applicationIdentifier))"
            content.body = "Please update your device to use this application".localized(desiredLanguage: getDesiredLanguage())
            content.categoryIdentifier = "alert"
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.001, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            switch settings.authorizationStatus {
                
            case .authorized:
                center.add(request)
            case .denied:
                uiLog.info("\("Application terminated without user notification", privacy: .public)")
            case .notDetermined:
                uiLog.info("\("Application terminated without user notification status", privacy: .public)")
            case .provisional:
                uiLog.info("\("Application terminated with provisional user notification status", privacy: .public)")
                center.add(request)
            @unknown default:
                uiLog.info("\("Application terminated with unknown user notification status", privacy: .public)")
            }
        }
    }
    
    func detectBannedShortcutKeys(with event: NSEvent) -> Bool {
        // Only detect shortcut keys if Nudge is active - adapted from https://stackoverflow.com/questions/32446978/swift-capture-keydown-from-nsviewcontroller/40465919
        if NSApplication.shared.isActive {
            switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
                // Disable CMD + W - closes the Nudge window and breaks it
                case [.command] where event.characters == "w":
                    uiLog.warning("\("Nudge detected an attempt to close the application via CMD + W shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + N - closes the Nudge window and breaks it
                case [.command] where event.characters == "n":
                    uiLog.warning("\("Nudge detected an attempt to create a new window via CMD + N shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + M - closes the Nudge window and breaks it
                case [.command] where event.characters == "m":
                    uiLog.warning("\("Nudge detected an attempt to minimise the application via CMD + M shortcut key.", privacy: .public)")
                    return true
                // Disable CMD + Q -  fully closes Nudge
                case [.command] where event.characters == "q":
                    uiLog.warning("\("Nudge detected an attempt to close the application via CMD + Q shortcut key.", privacy: .public)")
                    return true
                // Don't care about any other shortcut keys
                default:
                    return false
            }
        }
        return false
    }
    
    // Only exit if primaryQuitButton is clicked
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if nudgePrimaryState.shouldExit {
            return NSApplication.TerminateReply.terminateNow
        } else {
            uiLog.warning("\("Nudge detected an attempt to exit the application.", privacy: .public)")
            return NSApplication.TerminateReply.terminateCancel
        }
    }

    func runSoftwareUpdate() {
        if Utils().demoModeEnabled() || Utils().unitTestingEnabled() {
            return
        }

        if asynchronousSoftwareUpdate && Utils().requireMajorUpgrade() == false {
            DispatchQueue(label: "nudge-su", attributes: .concurrent).asyncAfter(deadline: .now(), execute: {
                SoftwareUpdate().Download()
            })
        } else {
            SoftwareUpdate().Download()
        }
    }

    // Pre-Launch Logic
    func applicationWillFinishLaunching(_ notification: Notification) {
        if FileManager.default.fileExists(atPath: "/Library/Managed Preferences/com.github.macadmins.Nudge.json.plist") {
            prefsProfileLog.warning("\("Found bad profile path at /Library/Managed Preferences/com.github.macadmins.Nudge.json.plist", privacy: .public)")
            exit(1)
        }
        
        if CommandLine.arguments.contains("-print-profile-config") {
            var nudgeProfileConfig = [String:Any]()
            nudgeProfileConfig["optionalFeatures"] = nudgeDefaults.dictionary(forKey: "optionalFeatures") as? [String:AnyObject]
            nudgeProfileConfig["osVersionRequirements"] = nudgeDefaults.array(forKey: "osVersionRequirements") as? [[String:AnyObject]]
            nudgeProfileConfig["userExperience"] = nudgeDefaults.dictionary(forKey: "userExperience") as? [String:AnyObject]
            nudgeProfileConfig["userInterface"] = nudgeDefaults.dictionary(forKey: "userInterface") as? [String:AnyObject]
            if nudgeProfileConfig.isEmpty {
                print("Could not find profile preferences!")
                exit(1)
            } else {
                do {
                    let plistData = try PropertyListSerialization.data(fromPropertyList: nudgeProfileConfig, format: .xml, options: 0)
                    let xmlPlistData = try XMLDocument.init(data: plistData, options: .nodePreserveAll)
                    let prettyXMLData = xmlPlistData.xmlData(options: .nodePrettyPrint)
                    let prettyXMLString = String(data: prettyXMLData, encoding: .utf8)
                    print(prettyXMLString as AnyObject)
                } catch {
                    print("issue with profile data!")
                    exit(1)
                }
            }
            exit(0)
        } else if CommandLine.arguments.contains("-print-json-config") {
            let nudgeJSONConfig = try? newJSONEncoder().encode(nudgeJSONPreferences)
            if ((nudgeJSONConfig) != nil) {
                if let json = try? JSONSerialization.jsonObject(with: newJSONEncoder().encode(nudgeJSONPreferences), options: .mutableContainers),
                   let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                    print(String(decoding: jsonData, as: UTF8.self))
                } else {
                    print("issue with JSON data!")
                    exit(1)
                }
            } else {
                print("Could not find JSON preferences!")
                exit(1)
            }
            exit(0)
        }

        // print("applicationWillFinishLaunching")
        _ = Utils().gracePeriodLogic()
        if nudgePrimaryState.shouldExit {
            exit(0)
        }

        if randomDelay {
            let randomDelaySeconds = Int.random(in: 1...maxRandomDelayInSeconds)
            uiLog.notice("Delaying initial run (in seconds) by: \(String(randomDelaySeconds), privacy: .public)")
            sleep(UInt32(randomDelaySeconds))
        }
        
        // Check to see if camera was turned off or on in the last x amount of minutes
        if logReferralTime > 0 && !nudgeLogState.afterFirstRun {
            LogReader().cameraShow()
            LogReader().screenSharingShow()
        }
        // Stream camera status from here on out
        LogReader().Stream()

        self.runSoftwareUpdate()
        if Utils().requireMajorUpgrade() {
            if actionButtonPath != nil {
                if !actionButtonPath!.isEmpty {
                    return
                } else {
                    prefsProfileLog.warning("\("actionButtonPath contains empty string - actionButton will be unable to trigger any action required for major upgrades", privacy: .public)")
                    return
                }
            }

            if attemptToFetchMajorUpgrade == true && fetchMajorUpgradeSuccessful == false && (majorUpgradeAppPathExists == false && majorUpgradeBackupAppPathExists == false) {
                uiLog.error("\("Unable to fetch major upgrade and application missing, exiting Nudge", privacy: .public)")
                nudgePrimaryState.shouldExit = true
                exit(1)
            } else if attemptToFetchMajorUpgrade == false && (majorUpgradeAppPathExists == false && majorUpgradeBackupAppPathExists == false) {
                uiLog.error("\("Unable to find major upgrade application, exiting Nudge", privacy: .public)")
                nudgePrimaryState.shouldExit = true
                exit(1)
            }
        }
    }
    
    class WindowDelegate: NSObject, NSWindowDelegate {
        func windowDidMove(_ notification: Notification) {
            Utils().centerNudge()
        }
        func windowDidChangeScreen(_ notification: Notification) {
            Utils().centerNudge()
        }
    }
}

@main
struct Main: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var viewState = nudgePrimaryState
    
    var declaredWindowHeight: CGFloat = 450
    var declaredWindowWidth: CGFloat = 900
    
    var body: some Scene {
        WindowGroup {
            if Utils().debugUIModeEnabled() {
                VSplitView {
                    ContentView(viewObserved: viewState)
                        .frame(width: declaredWindowWidth, height: declaredWindowHeight)
                    ContentView(viewObserved: viewState, forceSimpleMode: true)
                        .frame(width: declaredWindowWidth, height: declaredWindowHeight)
                }
                .frame(height: declaredWindowHeight*2)
            } else {
                ContentView(viewObserved: viewState)
                    .frame(width: declaredWindowWidth, height: declaredWindowHeight)
            }
        }
        // Hide Title Bar
        .windowStyle(.hiddenTitleBar)
    }
}
