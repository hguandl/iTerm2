//
//  InputSourceForcer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/23.
//

import Foundation
import Carbon

@objc(iTermInputSourceForcer)
class InputSourceForcer: NSObject {
    @objc(sharedInstance)
    static let instance = InputSourceForcer()
    private var begun = false
    private var systemLocale: String? {
        didSet {
            DLog("Set systemLocale to \(systemLocale ?? "(nil)")")
        }
    }
    private var active = false
    private var timer: Timer?

    private static var currentSystemLocale: String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        guard let inputSourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }

        let identifier = Unmanaged<CFString>.fromOpaque(inputSourceID).takeUnretainedValue() as String
        return identifier
    }

    override init() {
        systemLocale = Self.currentSystemLocale
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillResignActive),
                                               name: NSApplication.willResignActiveNotification,
                                               object: nil)
    }

    @objc
    func begin() {
        DLog("Begin input source forcing")
        assert(!begun)
        active = NSApp.isActive
        begun = true
        update()
        iTermPreferences.addObserver(forKey: kPreferenceKeyKeyboardLocale) { [weak self] _, _ in
            DLog("Keyboard locale pref changed")
            self?.update()
        }
        iTermPreferences.addObserver(forKey: kPreferenceKeyForceKeyboard) { [weak self] _, _ in
            DLog("Force keyboard pref changed")
            self?.update()
        }
    }

    @objc private func appDidBecomeActive(notification: Notification) {
        DLog("App did become active")
        systemLocale = Self.currentSystemLocale
        active = true
        update()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.timerDidFire()
        }
    }

    private func timerDidFire() {
        update()
    }

    @objc private func appWillResignActive(notification: Notification) {
        timer?.invalidate()
        timer = nil
        guard forcingEnabled else {
            DLog("Resigning active but input source forcing is not enabled")
            return
        }
        active = false
        if let systemLocale {
            DLog("Switch to \(systemLocale) when resigining active")
            setInputLocale(systemLocale)
        } else {
            DLog("App will resign active. Not changing input source.")
        }
    }

    private var forcingEnabled: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyForceKeyboard)
    }

    private var desiredLocale: String? {
        if !forcingEnabled {
            return nil
        }
        return iTermPreferences.string(forKey: kPreferenceKeyKeyboardLocale)
    }

    private func update() {
        guard forcingEnabled else {
            DLog("update: not enabled")
            return
        }
        guard active else {
            DLog("update: not active")
            return
        }
        guard let locale = self.desiredLocale ?? systemLocale else {
            DLog("update: no desired locale")
            return
        }
        DLog("update: switch to \(locale)")
        setInputLocale(locale)
    }

    private func setInputLocale(_ keyboardID: String) {
        precondition(forcingEnabled)
        let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        if let inputSource = inputSources.first(where: { inputSource in
            guard let idProperty = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
                return false
            }
            let id = Unmanaged<CFString>.fromOpaque(idProperty).takeUnretainedValue() as String
            return id == keyboardID
        }) {
            DLog("selectInputLocale: Found input source with id \(keyboardID) and selecting it")
            TISSelectInputSource(inputSource)
        } else {
            DLog("selectInputLocale: there is no input source with id \(keyboardID)")
        }
    }
}
