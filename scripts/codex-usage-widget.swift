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

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class UsageWidgetController: NSObject, NSWindowDelegate {
    private let store = UsageStore()
    private let panel: FloatingPanel
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

        let subtitle = NSTextField(labelWithString: "打开官方页面确认后填写")
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

        let openButton = NSButton(
            title: "打开官方用量页",
            target: self,
            action: #selector(openOfficialPage)
        )
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 120, y: 31, width: 132, height: 28)
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
            statusLabel.stringValue = "尚未保存本地用量"
            return
        }
        fiveHourField.stringValue = "\(snapshot.fiveHour.remainingPercent)"
        weeklyField.stringValue = "\(snapshot.weekly.remainingPercent)"
        statusLabel.stringValue = "已保存：\(Self.dateFormatter.string(from: snapshot.updatedAt))"
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
            statusLabel.stringValue = "已保存：\(Self.dateFormatter.string(from: snapshot.updatedAt))"
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
