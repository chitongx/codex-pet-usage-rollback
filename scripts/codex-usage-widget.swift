#!/usr/bin/env swift

import AppKit
import Foundation
import Darwin
import ObjectiveC.runtime
import QuartzCore

struct UsageWindow: Codable, Equatable {
    let usedPercent: Int
    let resetsAt: Date?
    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
    init(usedPercent: Int, resetsAt: Date? = nil) throws {
        guard (0...100).contains(usedPercent) else { throw UsageError.invalidPercentage }
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

struct UsageSnapshot: Codable, Equatable {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow
    let updatedAt: Date
}

enum UsageError: Error { case invalidPercentage }

final class UsageStore {
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("CodexUsageWidget", isDirectory: true)
        fileURL = directory.appendingPathComponent("usage.json")
    }

    func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
    }
}

enum LiveUsageError: LocalizedError {
    case codexCliNotFound, noRateLimitResponse, invalidRateLimitResponse, timedOut

    var errorDescription: String? {
        switch self {
        case .codexCliNotFound: "找不到 Codex CLI"
        case .noRateLimitResponse: "Codex 没有返回额度"
        case .invalidRateLimitResponse: "Codex 额度响应格式无法识别"
        case .timedOut: "读取 Codex 额度超时"
        }
    }
}

enum LiveUsageFetcher {
    private static let codexCandidates = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    static func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try fetchSnapshot() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func fetchSnapshot() throws -> UsageSnapshot {
        guard let executable = codexCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw LiveUsageError.codexCliNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try process.run()

        let initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex-touchbar-helper\",\"version\":\"1.0.0\"}}}\n"
        let request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}\n"
        input.fileHandleForWriting.write(Data((initialize + request).utf8))

        defer { if process.isRunning { process.terminate() } }
        let signal = DispatchSemaphore(value: 0)
        var response: [String: Any]?
        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { signal.signal(); return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: line),
                    let candidate = object as? [String: Any],
                    let id = candidate["id"] as? NSNumber,
                    id.intValue == 2
                else { continue }
                response = candidate
                signal.signal()
                return
            }
        }

        if signal.wait(timeout: .now() + 8) == .timedOut {
            output.fileHandleForReading.readabilityHandler = nil
            throw LiveUsageError.timedOut
        }
        output.fileHandleForReading.readabilityHandler = nil
        guard let response else { throw LiveUsageError.noRateLimitResponse }
        return try snapshot(from: response)
    }

    private static func snapshot(from response: [String: Any]) throws -> UsageSnapshot {
        guard
            let result = response["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any],
            let secondary = window(from: limits["secondary"])
        else { throw LiveUsageError.invalidRateLimitResponse }
        // Pro accounts may omit the primary (5-hour) window entirely.
        return UsageSnapshot(fiveHour: window(from: limits["primary"]), weekly: secondary, updatedAt: Date())
    }

    private static func window(from value: Any?) -> UsageWindow? {
        guard let dictionary = value as? [String: Any], let number = dictionary["usedPercent"] as? NSNumber else { return nil }
        let resetDate: Date?
        if let seconds = dictionary["resetsAt"] as? NSNumber {
            resetDate = Date(timeIntervalSince1970: seconds.doubleValue)
        } else {
            resetDate = nil
        }
        return try? UsageWindow(usedPercent: min(100, max(0, number.intValue)), resetsAt: resetDate)
    }
}

final class QuotaPillView: NSView {
    private let fillView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let backgroundGradient = CAGradientLayer()
    private let fillGradient = CAGradientLayer()
    private let shimmerGradient = CAGradientLayer()

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.46
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        backgroundGradient.frame = bounds
        backgroundGradient.cornerRadius = 8
        backgroundGradient.colors = [
            NSColor(white: 0.22, alpha: 0.96).cgColor,
            NSColor(white: 0.07, alpha: 0.98).cgColor
        ]
        backgroundGradient.startPoint = CGPoint(x: 0, y: 1)
        backgroundGradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.insertSublayer(backgroundGradient, at: 0)

        fillView.frame = NSRect(x: 0, y: 0, width: 0, height: bounds.height)
        fillView.wantsLayer = true
        fillView.layer?.cornerRadius = 8
        fillView.layer?.masksToBounds = true
        fillView.layer?.addSublayer(fillGradient)
        shimmerGradient.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.22).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ]
        shimmerGradient.locations = [0, 0.5, 1]
        shimmerGradient.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerGradient.endPoint = CGPoint(x: 1, y: 0.5)
        fillView.layer?.addSublayer(shimmerGradient)
        addSubview(fillView)
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        label.frame = bounds.insetBy(dx: 8, dy: 2)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func update(text: String, remaining: Int) {
        let accent: NSColor
        switch remaining {
        case 0...20: accent = .systemRed
        case 21...50: accent = .systemOrange
        default: accent = .systemGreen
        }
        label.stringValue = text
        layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
        let targetFrame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(100, remaining))) / 100, height: bounds.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.7
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fillView.animator().frame = targetFrame
        } completionHandler: { [weak self] in
            self?.syncAnimatedLayers()
        }
        fillGradient.frame = fillView.bounds
        fillGradient.cornerRadius = 8
        fillGradient.colors = [
            accent.withAlphaComponent(0.92).cgColor,
            accent.withAlphaComponent(0.58).cgColor
        ]
        fillGradient.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradient.endPoint = CGPoint(x: 1, y: 0.5)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.78
        pulse.toValue = 1.0
        pulse.duration = 2.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        fillGradient.add(pulse, forKey: "softPulse")
        syncAnimatedLayers()
    }

    private func syncAnimatedLayers() {
        fillGradient.frame = fillView.bounds
        let width = max(24, fillView.bounds.width)
        shimmerGradient.frame = NSRect(x: -width, y: 0, width: width, height: bounds.height)
        shimmerGradient.removeAnimation(forKey: "shimmer")
        guard fillView.bounds.width > 1 else { return }
        let shimmer = CABasicAnimation(keyPath: "transform.translation.x")
        shimmer.fromValue = -width
        shimmer.toValue = fillView.bounds.width + width
        shimmer.duration = 2.8
        shimmer.repeatCount = .infinity
        shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerGradient.add(shimmer, forKey: "shimmer")
    }
}

final class CodexTouchBarController: NSObject, NSTouchBarDelegate {
    static let remIdentifier = NSTouchBarItem.Identifier("codexUsage.rem")
    static let fiveHourIdentifier = NSTouchBarItem.Identifier("codexUsage.fiveHour")
    static let weeklyIdentifier = NSTouchBarItem.Identifier("codexUsage.weekly")

    let touchBar: NSTouchBar
    private let remItem: NSCustomTouchBarItem
    private let fiveHourItem: NSCustomTouchBarItem
    private let weeklyItem: NSCustomTouchBarItem
    private let fiveHourPill = QuotaPillView(width: 170)
    private let weeklyPill = QuotaPillView(width: 210)

    override init() {
        remItem = NSCustomTouchBarItem(identifier: Self.remIdentifier)
        fiveHourItem = NSCustomTouchBarItem(identifier: Self.fiveHourIdentifier)
        weeklyItem = NSCustomTouchBarItem(identifier: Self.weeklyIdentifier)
        touchBar = NSTouchBar()
        super.init()

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 42, height: 30))
        imageView.image = Self.remImage()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        remItem.view = imageView
        remItem.customizationLabel = "雷姆"
        fiveHourItem.view = fiveHourPill
        weeklyItem.view = weeklyPill
        fiveHourItem.customizationLabel = "5 小时额度"
        weeklyItem.customizationLabel = "1 周额度"

        touchBar.delegate = self
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("codexUsage")
        touchBar.defaultItemIdentifiers = [Self.remIdentifier, Self.fiveHourIdentifier, Self.weeklyIdentifier]
        touchBar.customizationAllowedItemIdentifiers = [Self.remIdentifier, Self.fiveHourIdentifier, Self.weeklyIdentifier]
    }

    func update(snapshot: UsageSnapshot) {
        if let fiveHour = snapshot.fiveHour {
            fiveHourPill.update(text: "5小时 \(fiveHour.remainingPercent)%", remaining: fiveHour.remainingPercent)
        } else {
            fiveHourPill.update(text: "Pro 无5小时限制", remaining: 100)
        }
        weeklyPill.update(text: "1周 \(snapshot.weekly.remainingPercent)% · \(Self.remainingUntilReset(snapshot.weekly.resetsAt))", remaining: snapshot.weekly.remainingPercent)
    }

    func showUnavailable() {
        fiveHourPill.update(text: "5小时 --", remaining: 0)
        weeklyPill.update(text: "1周 -- · --", remaining: 0)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.remIdentifier: remItem
        case Self.fiveHourIdentifier: fiveHourItem
        case Self.weeklyIdentifier: weeklyItem
        default: nil
        }
    }

    private static func remImage() -> NSImage? {
        let bundledPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexUsageWidget/Resources/rem.png")
        let image: NSImage?
        if let custom = NSImage(contentsOf: customCharacterURL) {
            image = custom
        } else {
            image = NSImage(contentsOf: bundledPath)
        }
        guard let image else { return nil }
        image.size = NSSize(width: 20, height: 30)
        return image
    }

    private static var customCharacterURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codex-touchbar/character.png")
    }

    static func remImageForStatusItem() -> NSImage? {
        guard let image = remImage() else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func remainingUntilReset(_ date: Date?) -> String {
        guard let date else { return "--" }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "已重置" }
        let days = Int(ceil(seconds / 86_400))
        if days >= 1 { return "还有\(days)天" }
        let hours = max(1, Int(ceil(seconds / 3_600)))
        return "还有\(hours)小时"
    }
}

protocol SystemModalTouchBarRuntime {
    func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool
    func setTrayPresence(_ visible: Bool, identifier: NSTouchBarItem.Identifier)
    func setCloseBoxVisible(_ visible: Bool)
    func present(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) -> Bool
    func dismiss(_ touchBar: NSTouchBar) -> Bool
}

final class PrivateSystemModalRuntime: SystemModalTouchBarRuntime {
    private typealias PresentFunction = @convention(c) (AnyClass, Selector, NSTouchBar, NSTouchBarItem.Identifier?) -> Void
    private typealias DismissFunction = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
    private typealias AddTrayFunction = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
    private typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBoxFunction = @convention(c) (Bool) -> Void

    private let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")
    private let addTraySelector = NSSelectorFromString("addSystemTrayItem:")
    private let runtimeHandle: UnsafeMutableRawPointer?

    init() {
        runtimeHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW) ?? dlopen(nil, RTLD_NOW)
    }

    func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        guard let method = class_getClassMethod(NSTouchBarItem.self, addTraySelector) else { return false }
        let function = unsafeBitCast(method_getImplementation(method), to: AddTrayFunction.self)
        function(NSTouchBarItem.self, addTraySelector, item)
        return true
    }

    func setTrayPresence(_ visible: Bool, identifier: NSTouchBarItem.Identifier) {
        guard let runtimeHandle, let symbol = dlsym(runtimeHandle, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        let function = unsafeBitCast(symbol, to: PresenceFunction.self)
        function(identifier.rawValue as NSString, visible)
    }

    func setCloseBoxVisible(_ visible: Bool) {
        guard let runtimeHandle, let symbol = dlsym(runtimeHandle, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        let function = unsafeBitCast(symbol, to: CloseBoxFunction.self)
        function(visible)
    }

    func present(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) -> Bool {
        guard let method = class_getClassMethod(NSTouchBar.self, presentSelector) else { return false }
        let function = unsafeBitCast(method_getImplementation(method), to: PresentFunction.self)
        function(NSTouchBar.self, presentSelector, touchBar, trayIdentifier)
        return true
    }

    func dismiss(_ touchBar: NSTouchBar) -> Bool {
        guard let method = class_getClassMethod(NSTouchBar.self, dismissSelector) else { return false }
        let function = unsafeBitCast(method_getImplementation(method), to: DismissFunction.self)
        function(NSTouchBar.self, dismissSelector, touchBar)
        return true
    }

    var isAvailable: Bool {
        guard runtimeHandle != nil else { return false }
        return class_getClassMethod(NSTouchBar.self, presentSelector) != nil
            && class_getClassMethod(NSTouchBar.self, dismissSelector) != nil
            && class_getClassMethod(NSTouchBarItem.self, addTraySelector) != nil
            && dlsym(runtimeHandle, "DFRElementSetControlStripPresenceForIdentifier") != nil
    }
}

final class SystemModalTouchBarPresenter {
    private let runtime: PrivateSystemModalRuntime
    private let controller: CodexTouchBarController
    private let trayIdentifier = NSTouchBarItem.Identifier("com.chitongx.codexUsage.controlStrip")
    private var trayItem: NSCustomTouchBarItem?
    private var isPresented = false

    init(controller: CodexTouchBarController) {
        runtime = PrivateSystemModalRuntime()
        self.controller = controller
    }

    func prepare() -> Bool {
        guard runtime.isAvailable else {
            NSLog("Codex Touch Bar: system modal API unavailable")
            return false
        }
        if trayItem != nil { return true }
        let item = NSCustomTouchBarItem(identifier: trayIdentifier)
        let button = NSButton(image: CodexTouchBarController.remImageForStatusItem() ?? NSImage(), target: nil, action: nil)
        item.view = button
        guard runtime.addSystemTrayItem(item) else {
            NSLog("Codex Touch Bar: addSystemTrayItem failed")
            return false
        }
        trayItem = item
        runtime.setTrayPresence(true, identifier: trayIdentifier)
        return true
    }

    func show() {
        guard prepare() else { return }
        runtime.setCloseBoxVisible(false)
        if runtime.present(controller.touchBar, trayIdentifier: trayIdentifier) { isPresented = true }
    }

    func hide() {
        if isPresented {
            _ = runtime.dismiss(controller.touchBar)
            isPresented = false
        }
        runtime.setTrayPresence(false, identifier: trayIdentifier)
        runtime.setCloseBoxVisible(true)
    }
}

final class CodexTouchBarAppController: NSObject {
    private static let codexBundleIDs = Set(["com.openai.codex", "com.openai.chatgpt"])
    private let store = UsageStore()
    private let touchBarController = CodexTouchBarController()
    private lazy var presenter = SystemModalTouchBarPresenter(controller: touchBarController)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var refreshTimer: Timer?

    func start() {
        configureStatusItem()
        touchBarController.showUnavailable()
        refreshLiveUsage()
        refreshTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refreshLiveUsage), userInfo: nil, repeats: true)
        refreshTimer?.tolerance = 10
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.syncToFrontmostApplication() }
    }

    deinit {
        refreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        presenter.hide()
    }

    private func configureStatusItem() {
        statusItem.button?.image = CodexTouchBarController.remImageForStatusItem()
        statusItem.button?.toolTip = "Codex 用量 Touch Bar（仅 Codex 聚焦时显示）"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "刷新额度", action: #selector(refreshLiveUsage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "重新显示（仅 Codex 聚焦时）", action: #selector(syncToFrontmostApplication), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.syncToFrontmostApplication() }
    }

    @objc private func syncToFrontmostApplication() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let bundleID, Self.codexBundleIDs.contains(bundleID) { presenter.show() }
        else { presenter.hide() }
    }

    @objc private func refreshLiveUsage() {
        LiveUsageFetcher.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                try? store.save(snapshot)
                touchBarController.update(snapshot: snapshot)
                if let fiveHour = snapshot.fiveHour {
                    statusItem.button?.toolTip = "Codex 5小时剩余 \(fiveHour.remainingPercent)% · 仅 Codex 聚焦时显示"
                } else {
                    statusItem.button?.toolTip = "Codex Pro · 无5小时限额 · 仅 Codex 聚焦时显示"
                }
            case let .failure(error):
                if let fallback = store.load() { touchBarController.update(snapshot: fallback) }
                else { touchBarController.showUnavailable() }
                NSLog("Codex usage refresh failed: %@", error.localizedDescription)
            }
        }
    }

    @objc private func quit() {
        presenter.hide()
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CodexTouchBarAppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = CodexTouchBarAppController()
        controller?.start()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
