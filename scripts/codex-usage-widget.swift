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

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class UsageWidgetController: NSObject, NSWindowDelegate {
    private let store = UsageStore()
    private let panel: FloatingPanel
    private var refreshTimer: Timer?
    private let fiveHourField = NSTextField(string: "")
    private let weeklyField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(labelWithString: "")

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildView()
        loadSnapshot()
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
    }

    private func buildView() {
        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentView

        let imageView = NSImageView(frame: NSRect(x: 0, y: 18, width: 245, height: 375))
        let imagePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexUsageWidget/Resources/rem.png")
        imageView.image = NSImage(contentsOf: imagePath)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        contentView.addSubview(imageView)

        let card = NSVisualEffectView(frame: NSRect(x: 205, y: 82, width: 275, height: 256))
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 22
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        contentView.addSubview(card)

        let title = NSTextField(labelWithString: "Codex 用量")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: 22, y: 211, width: 220, height: 30)
        card.addSubview(title)

        let subtitle = NSTextField(labelWithString: "只读读取 Codex，失败时保留上次数据")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.72)
        subtitle.frame = NSRect(x: 22, y: 191, width: 230, height: 18)
        card.addSubview(subtitle)

        addUsageRow(to: card, label: "5 小时剩余", field: fiveHourField, y: 143)
        addUsageRow(to: card, label: "1 周剩余", field: weeklyField, y: 101)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        statusLabel.frame = NSRect(x: 22, y: 72, width: 230, height: 16)
        card.addSubview(statusLabel)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveSnapshot))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 22, y: 31, width: 92, height: 28)
        card.addSubview(saveButton)

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshLiveUsage))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 120, y: 31, width: 66, height: 28)
        card.addSubview(refreshButton)

        let openButton = NSButton(
            title: "打开官方用量页",
            target: self,
            action: #selector(openOfficialPage)
        )
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 190, y: 31, width: 82, height: 28)
        card.addSubview(openButton)

        feedbackLabel.font = .systemFont(ofSize: 10)
        feedbackLabel.textColor = NSColor.systemYellow
        feedbackLabel.frame = NSRect(x: 22, y: 10, width: 230, height: 16)
        card.addSubview(feedbackLabel)

        let closeButton = NSButton(title: "×", target: self, action: #selector(hidePanel))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 22, weight: .light)
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        closeButton.frame = NSRect(x: 450, y: 350, width: 30, height: 30)
        contentView.addSubview(closeButton)
    }

    private func addUsageRow(to card: NSVisualEffectView, label: String, field: NSTextField, y: CGFloat) {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 13, weight: .medium)
        labelField.textColor = .white
        labelField.frame = NSRect(x: 22, y: y + 4, width: 125, height: 20)
        card.addSubview(labelField)

        field.alignment = .right
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.placeholderString = "0–100"
        field.focusRingType = .none
        field.frame = NSRect(x: 165, y: y, width: 87, height: 28)
        card.addSubview(field)

        let percent = NSTextField(labelWithString: "%")
        percent.font = .systemFont(ofSize: 13)
        percent.textColor = NSColor.white.withAlphaComponent(0.75)
        percent.frame = NSRect(x: 253, y: y + 4, width: 18, height: 20)
        card.addSubview(percent)
    }

    private func loadSnapshot() {
        guard let snapshot = store.load() else {
            statusLabel.stringValue = "正在读取 Codex 额度…"
            refreshLiveUsage()
            return
        }
        apply(snapshot, status: "上次数据：\(Self.dateFormatter.string(from: snapshot.updatedAt))")
        refreshLiveUsage()
    }

    @objc private func refreshLiveUsage() {
        statusLabel.stringValue = "正在读取 Codex 额度…"
        LiveUsageFetcher.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                try? self.store.save(snapshot)
                self.apply(snapshot, status: "自动更新：\(Self.dateFormatter.string(from: snapshot.updatedAt))")
                self.feedbackLabel.stringValue = ""
            case let .failure(error):
                let fallback = self.store.load()
                if let fallback {
                    self.apply(fallback, status: "自动读取失败，显示上次数据")
                } else {
                    self.statusLabel.stringValue = "自动读取失败，请手动填写"
                }
                self.feedbackLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot, status: String) {
        fiveHourField.stringValue = "\(snapshot.fiveHour.remainingPercent)"
        weeklyField.stringValue = "\(snapshot.weekly.remainingPercent)"
        statusLabel.stringValue = status
    }

    @objc private func saveSnapshot() {
        guard
            let fiveHourRemaining = Int(fiveHourField.stringValue),
            let weeklyRemaining = Int(weeklyField.stringValue),
            (0...100).contains(fiveHourRemaining),
            (0...100).contains(weeklyRemaining)
        else {
            feedbackLabel.stringValue = "请输入 0–100 的剩余百分比"
            return
        }

        do {
            let snapshot = UsageSnapshot(
                fiveHour: try UsageWindow(usedPercent: 100 - fiveHourRemaining),
                weekly: try UsageWindow(usedPercent: 100 - weeklyRemaining),
                updatedAt: Date()
            )
            try store.save(snapshot)
            statusLabel.stringValue = "已手动保存：\(Self.dateFormatter.string(from: snapshot.updatedAt))"
            feedbackLabel.stringValue = ""
        } catch {
            feedbackLabel.stringValue = "保存失败，请重试"
        }
    }

    @objc private func openOfficialPage() {
        guard let url = URL(string: "https://help.openai.com/en/articles/20001478") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func hidePanel() {
        panel.orderOut(nil)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: UsageWidgetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = UsageWidgetController()
        controller?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
