#!/usr/bin/env swift

import AppKit
import Foundation

struct UsageWindow: Codable, Equatable {
    let usedPercent: Int

    var remainingPercent: Int { 100 - usedPercent }

    init(usedPercent: Int) throws {
        guard (0...100).contains(usedPercent) else {
            throw UsageError.invalidPercentage
        }
        self.usedPercent = usedPercent
    }
}

struct UsageSnapshot: Codable, Equatable {
    let fiveHour: UsageWindow
    let weekly: UsageWindow
    let updatedAt: Date
}

enum UsageError: Error {
    case invalidPercentage
}

final class UsageStore {
    private let fileURL: URL

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = applicationSupport.appendingPathComponent("CodexUsageWidget", isDirectory: true)
        fileURL = directory.appendingPathComponent("usage.json")
    }

    func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
    }
}

enum LiveUsageError: LocalizedError {
    case codexCliNotFound
    case noRateLimitResponse
    case invalidRateLimitResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .codexCliNotFound:
            return "找不到 Codex CLI"
        case .noRateLimitResponse:
            return "Codex 没有返回额度"
        case .invalidRateLimitResponse:
            return "Codex 额度响应格式无法识别"
        case .timedOut:
            return "读取 Codex 额度超时"
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
            let result = Result { try self.fetchSnapshot() }
            DispatchQueue.main.async {
                completion(result)
            }
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

        let initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex-usage-widget\",\"version\":\"0.1.0\"}}}\n"
        let request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}\n"
        input.fileHandleForWriting.write(Data((initialize + request).utf8))

        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let responseSignal = DispatchSemaphore(value: 0)
        var response: [String: Any]?
        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                responseSignal.signal()
                return
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: line),
                    let candidate = object as? [String: Any],
                    let id = candidate["id"] as? NSNumber,
                    id.intValue == 2
                else {
                    continue
                }
                response = candidate
                responseSignal.signal()
                return
            }
        }

        if responseSignal.wait(timeout: .now() + 8) == .timedOut {
            output.fileHandleForReading.readabilityHandler = nil
            throw LiveUsageError.timedOut
        }
        output.fileHandleForReading.readabilityHandler = nil

        guard let response else {
            throw LiveUsageError.noRateLimitResponse
        }
        return try snapshot(from: response)
    }

    private static func snapshot(from response: [String: Any]) throws -> UsageSnapshot {
        guard
            let result = response["result"] as? [String: Any],
            let rateLimits = result["rateLimits"] as? [String: Any],
            let primary = window(from: rateLimits["primary"]),
            let secondary = window(from: rateLimits["secondary"])
        else {
            throw LiveUsageError.invalidRateLimitResponse
        }

        return UsageSnapshot(
            fiveHour: primary,
            weekly: secondary,
            updatedAt: Date()
        )
    }

    private static func window(from value: Any?) -> UsageWindow? {
        guard
            let dictionary = value as? [String: Any],
            let number = dictionary["usedPercent"] as? NSNumber
        else {
            return nil
        }
        return try? UsageWindow(usedPercent: min(100, max(0, number.intValue)))
    }
}

final class QuotaPillView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = bounds.insetBy(dx: 8, dy: 3)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, accent: NSColor) {
        label.stringValue = text
        layer?.borderColor = accent.withAlphaComponent(0.62).cgColor
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
    private let fiveHourPill = QuotaPillView(width: 142)
    private let weeklyPill = QuotaPillView(width: 142)

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
        fiveHourItem.customizationLabel = "5 小时额度"
        weeklyItem.view = weeklyPill
        weeklyItem.customizationLabel = "1 周额度"

        touchBar.delegate = self
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("codexUsage")
        touchBar.defaultItemIdentifiers = [
            Self.remIdentifier,
            .flexibleSpace,
            Self.fiveHourIdentifier,
            Self.weeklyIdentifier
        ]
        touchBar.customizationAllowedItemIdentifiers = [
            Self.remIdentifier,
            Self.fiveHourIdentifier,
            Self.weeklyIdentifier,
            .flexibleSpace
        ]
        touchBar.principalItemIdentifier = Self.fiveHourIdentifier
    }

    func update(snapshot: UsageSnapshot) {
        fiveHourPill.update(
            text: "5小时 (snapshot.fiveHour.remainingPercent)%",
            accent: Self.accent(for: snapshot.fiveHour.remainingPercent)
        )
        weeklyPill.update(
            text: "每周 (snapshot.weekly.remainingPercent)%",
            accent: Self.accent(for: snapshot.weekly.remainingPercent)
        )
    }

    func showUnavailable() {
        fiveHourPill.update(text: "5小时 --", accent: .systemGray)
        weeklyPill.update(text: "每周 --", accent: .systemGray)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.remIdentifier:
            return remItem
        case Self.fiveHourIdentifier:
            return fiveHourItem
        case Self.weeklyIdentifier:
            return weeklyItem
        default:
            return nil
        }
    }

    private static func remImage() -> NSImage? {
        let imagePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexUsageWidget/Resources/rem.png")
        return NSImage(contentsOf: imagePath)
    }

    static func remImageForStatusItem() -> NSImage? {
        guard let image = remImage() else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func accent(for remaining: Int) -> NSColor {
        switch remaining {
        case 0...20:
            return .systemRed
        case 21...50:
            return .systemOrange
        default:
            return .systemGreen
        }
    }
}

final class TouchBarAppController: NSObject {
    private let store = UsageStore()
    private let touchBarController = CodexTouchBarController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var refreshTimer: Timer?

    func start() {
        configureStatusItem()
        NSApp.touchBar = touchBarController.touchBar
        NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        refreshLiveUsage()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshLiveUsage),
            userInfo: nil,
            repeats: true
        )
        refreshTimer?.tolerance = 10
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = CodexTouchBarController.remImageForStatusItem()
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "Codex 用量 Touch Bar"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "刷新额度", action: #selector(refreshLiveUsage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "激活 Touch Bar", action: #selector(activateTouchBar), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func refreshLiveUsage() {
        LiveUsageFetcher.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                try? self.store.save(snapshot)
                self.touchBarController.update(snapshot: snapshot)
                self.updateStatusIcon(remaining: snapshot.fiveHour.remainingPercent)
            case let .failure(error):
                let fallback = self.store.load()
                if let fallback {
                    self.touchBarController.update(snapshot: fallback)
                    self.updateStatusIcon(remaining: fallback.fiveHour.remainingPercent)
                } else {
                    self.touchBarController.showUnavailable()
                }
                NSLog("Codex usage refresh failed: %@", error.localizedDescription)
            }
        }
    }

    @objc private func activateTouchBar() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.touchBar = touchBarController.touchBar
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusIcon(remaining: Int) {
        statusItem.button?.title = ""
        statusItem.button?.toolTip = "Codex 5小时剩余 \(remaining)% · Touch Bar"
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TouchBarAppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = TouchBarAppController()
        controller?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
