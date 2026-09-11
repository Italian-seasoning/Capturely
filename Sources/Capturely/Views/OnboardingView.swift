import SwiftUI

struct OnboardingReadiness: Equatable {
    enum PrimaryAction: Equatable {
        case requestScreenRecording
        case requestMicrophone
        case enterCapturely
    }

    enum ItemStatus: String, Equatable {
        case required = "REQUIRED"
        case ready = "READY"
        case optional = "OPTIONAL"
        case later = "LATER"
        case armed = "ARMED"
    }

    var primaryAction: PrimaryAction
    var screenRecordingStatus: ItemStatus
    var microphoneStatus: ItemStatus
    var notificationsStatus: ItemStatus

    var primaryTitle: String {
        switch primaryAction {
        case .requestScreenRecording:
            return "Request Access"
        case .requestMicrophone:
            return "Request Microphone"
        case .enterCapturely:
            return "Enter Capturely"
        }
    }

    var canEnterCapturely: Bool {
        primaryAction == .enterCapturely
    }

    static func evaluate(settings: AppSettings, permissionSummary: PermissionSummary) -> OnboardingReadiness {
        let screenStatus: ItemStatus = permissionSummary.screenCaptureGranted ? .ready : .required
        let microphoneStatus: ItemStatus
        if settings.recordsMicrophone {
            microphoneStatus = permissionSummary.microphoneGranted ? .ready : .required
        } else {
            microphoneStatus = .optional
        }

        let primaryAction: PrimaryAction
        if !permissionSummary.screenCaptureGranted {
            primaryAction = .requestScreenRecording
        } else if settings.recordsMicrophone && !permissionSummary.microphoneGranted {
            primaryAction = .requestMicrophone
        } else {
            primaryAction = .enterCapturely
        }

        return OnboardingReadiness(
            primaryAction: primaryAction,
            screenRecordingStatus: screenStatus,
            microphoneStatus: microphoneStatus,
            notificationsStatus: permissionSummary.notificationsGranted ? .ready : .optional
        )
    }

    static func bufferLabel(settings: AppSettings) -> String {
        switch settings.replayDurationSeconds {
        case 30:
            return "30s buffer"
        case 60:
            return "60s buffer"
        case 120:
            return "2m buffer"
        case 300:
            return "5m buffer"
        default:
            return "\(settings.replayDurationSeconds)s buffer"
        }
    }

    static func hotkeyLabel(settings: AppSettings) -> String {
        settings.saveClipHotkey.displayValue
    }

    static func saveLocationLabel(settings: AppSettings) -> String {
        settings.clipLibraryURL?.path(percentEncoded: false) ?? "~/Movies/Capturely/Clips"
    }
}

enum OnboardingPage: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case access = "Access"
    case replay = "Replay"
    case ready = "Ready"

    var id: String { rawValue }

    var number: String {
        switch self {
        case .welcome:
            return "01"
        case .access:
            return "02"
        case .replay:
            return "03"
        case .ready:
            return "04"
        }
    }

    var title: String {
        rawValue
    }

    var headline: String {
        switch self {
        case .welcome:
            return "CAPTURE EVERY PLAY."
        case .access:
            return "GRANT ACCESS."
        case .replay:
            return "SET YOUR REPLAY."
        case .ready:
            return "SYSTEM READY."
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Instant replay for your best moments."
        case .access:
            return "Just the essentials."
        case .replay:
            return "Choose how clips are saved."
        case .ready:
            return "Replay engine armed."
        }
    }
}

enum OnboardingReplayGroup: String, CaseIterable, Identifiable, Hashable {
    case length = "Length"
    case quality = "Quality"
    case hotkey = "Hotkey"
    case storage = "Storage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .length:
            return "timer"
        case .quality:
            return "slider.horizontal.3"
        case .hotkey:
            return "keyboard"
        case .storage:
            return "folder"
        }
    }

    var detail: String {
        switch self {
        case .length:
            return "How far back the replay buffer reaches."
        case .quality:
            return "Balance sharpness, storage, and capture overhead."
        case .hotkey:
            return "The shortcut that saves the current replay."
        case .storage:
            return "Where clips land after they are saved."
        }
    }
}

struct OnboardingView: View {
    var settings: AppSettings = .defaults
    var permissionSummary: PermissionSummary = PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked")
    var completeOnboarding: () -> Void = {}
    var openSettings: () -> Void = {}
    var requestScreenCapturePermission: () -> Void = {}
    var requestMicrophonePermission: () -> Void = {}
    var requestNotificationsPermission: () -> Void = {}
    var setReplayDuration: (Int) -> Void = { _ in }
    var setSaveClipHotkey: (SaveClipHotkey) -> Void = { _ in }
    var setSelectedPreset: (CapturePreset.ID) -> Void = { _ in }
    var chooseClipLibrary: () -> Void = {}
    var resetClipLibrary: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnline = false
    @State private var selectedPage: OnboardingPage = .welcome
    @State private var selectedReplayGroup: OnboardingReplayGroup = .length

    init(
        settings: AppSettings = .defaults,
        permissionSummary: PermissionSummary = PermissionSummary(microphoneGranted: false, screenCaptureStatus: "Not checked"),
        completeOnboarding: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {},
        requestScreenCapturePermission: @escaping () -> Void = {},
        requestMicrophonePermission: @escaping () -> Void = {},
        requestNotificationsPermission: @escaping () -> Void = {},
        setReplayDuration: @escaping (Int) -> Void = { _ in },
        setSaveClipHotkey: @escaping (SaveClipHotkey) -> Void = { _ in },
        setSelectedPreset: @escaping (CapturePreset.ID) -> Void = { _ in },
        chooseClipLibrary: @escaping () -> Void = {},
        resetClipLibrary: @escaping () -> Void = {},
        initialPage: OnboardingPage = .welcome,
        initialReplayGroup: OnboardingReplayGroup = .length
    ) {
        self.settings = settings
        self.permissionSummary = permissionSummary
        self.completeOnboarding = completeOnboarding
        self.openSettings = openSettings
        self.requestScreenCapturePermission = requestScreenCapturePermission
        self.requestMicrophonePermission = requestMicrophonePermission
        self.requestNotificationsPermission = requestNotificationsPermission
        self.setReplayDuration = setReplayDuration
        self.setSaveClipHotkey = setSaveClipHotkey
        self.setSelectedPreset = setSelectedPreset
        self.chooseClipLibrary = chooseClipLibrary
        self.resetClipLibrary = resetClipLibrary
        _selectedPage = State(initialValue: initialPage)
        _selectedReplayGroup = State(initialValue: initialReplayGroup)
    }

    var readiness: OnboardingReadiness {
        OnboardingReadiness.evaluate(settings: settings, permissionSummary: permissionSummary)
    }

    func performPrimaryAction() {
        switch readiness.primaryAction {
        case .requestScreenRecording:
            requestScreenCapturePermission()
        case .requestMicrophone:
            requestMicrophonePermission()
        case .enterCapturely:
            completeOnboarding()
        }
    }

    func performPagePrimaryAction() {
        switch selectedPage {
        case .welcome, .replay:
            advancePage()
        case .access:
            switch readiness.primaryAction {
            case .requestScreenRecording, .requestMicrophone:
                performPrimaryAction()
            case .enterCapturely:
                advancePage()
            }
        case .ready:
            completeOnboarding()
        }
    }

    func advancePage() {
        guard let index = Self.pageIndex(selectedPage), index < OnboardingPage.allCases.count - 1 else { return }
        setPage(OnboardingPage.allCases[index + 1])
    }

    func retreatPage() {
        guard let index = Self.pageIndex(selectedPage), index > 0 else { return }
        setPage(OnboardingPage.allCases[index - 1])
    }

    private static func pageIndex(_ page: OnboardingPage) -> Int? {
        OnboardingPage.allCases.firstIndex(of: page)
    }

    private func setPage(_ page: OnboardingPage) {
        if reduceMotion {
            selectedPage = page
        } else {
            withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
                selectedPage = page
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 720
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStepRail(selectedPage: selectedPage, selectPage: setPage)
                    .onboardingReveal(isOnline: isOnline, index: 0, reduceMotion: reduceMotion)

                contentLayout(isCompact: isCompact)
                    .padding(.vertical, 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onboardingReveal(isOnline: isOnline, index: 1, reduceMotion: reduceMotion)

                Spacer(minLength: 0)

                OnboardingCommandRail(
                    selectedPage: selectedPage,
                    primaryTitle: commandRailPrimaryTitle,
                    primaryAction: performPagePrimaryAction
                )
                .onboardingReveal(isOnline: isOnline, index: 2, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 12)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(onboardingBackground)
        .onAppear {
            guard !isOnline else { return }
            if reduceMotion {
                isOnline = true
            } else {
                withAnimation(.smooth(duration: 0.52, extraBounce: 0)) {
                    isOnline = true
                }
            }
        }
    }
}

private extension OnboardingView {
    @ViewBuilder
    func contentLayout(isCompact: Bool) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 14) {
                leftPane
                clipPreview
            }
        } else {
            HStack(alignment: .top, spacing: 24) {
                leftPane
                    .frame(minWidth: 320, idealWidth: leftPaneIdealWidth, maxWidth: leftPaneMaxWidth, alignment: .topLeading)
                clipPreview
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(selectedPage.headline)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(CyberTheme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.60)
                    .fixedSize(horizontal: false, vertical: true)

                Text(selectedPage.subtitle)
                    .font(.callout.monospaced())
                    .foregroundStyle(CyberTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            pageControls
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var leftPaneIdealWidth: CGFloat {
        selectedPage == .replay ? 430 : 360
    }

    var leftPaneMaxWidth: CGFloat {
        selectedPage == .replay ? 470 : 400
    }

    @ViewBuilder
    var pageControls: some View {
        switch selectedPage {
        case .welcome:
            EmptyView()
        case .access:
            VStack(alignment: .leading, spacing: 8) {
                OnboardingAccessRow(
                    title: "Screen Recording",
                    status: readiness.screenRecordingStatus,
                    systemImage: "display",
                    actionTitle: permissionSummary.screenCaptureGranted ? nil : "Request",
                    action: requestScreenCapturePermission
                )
                .accessibilityIdentifier("onboarding.access.screen-recording")
                OnboardingAccessRow(
                    title: "System Audio",
                    status: settings.recordsSystemAudio ? .ready : .optional,
                    systemImage: "speaker.wave.2",
                    actionTitle: nil,
                    action: {}
                )
                .accessibilityIdentifier("onboarding.access.system-audio")
                OnboardingAccessRow(
                    title: "Microphone",
                    status: readiness.microphoneStatus,
                    systemImage: "mic",
                    actionTitle: permissionSummary.microphoneGranted ? nil : permissionSummary.microphoneActionTitle,
                    action: requestMicrophonePermission
                )
                .accessibilityIdentifier("onboarding.access.microphone")
                OnboardingAccessRow(
                    title: "Notifications",
                    status: readiness.notificationsStatus,
                    systemImage: "bell",
                    actionTitle: permissionSummary.notificationsGranted ? nil : permissionSummary.notificationsActionTitle,
                    action: requestNotificationsPermission
                )
                .accessibilityIdentifier("onboarding.access.notifications")
            }
        case .replay:
            VStack(alignment: .leading, spacing: 10) {
                OnboardingReplayGroupPicker(
                    selectedGroup: selectedReplayGroup,
                    selectGroup: setReplayGroup
                )
                OnboardingReplayGroupDetail(
                    group: selectedReplayGroup,
                    value: replayGroupValue(selectedReplayGroup),
                    controls: replayGroupControls(selectedReplayGroup)
                )
            }
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                OnboardingHeroButton(
                    title: "Start Capturing",
                    tone: .primary,
                    accessibilityIdentifier: "onboarding.ready.start-capturing",
                    action: completeOnboarding
                )
                OnboardingAccessRow(
                    title: "Replay Engine",
                    status: .armed,
                    systemImage: "record.circle",
                    actionTitle: nil,
                    action: {}
                )
                OnboardingAccessRow(
                    title: "Storage",
                    status: .ready,
                    systemImage: "externaldrive",
                    actionTitle: nil,
                    action: {}
                )
            }
        }
    }

    var clipPreview: some View {
        OnboardingClipPreviewStack(page: selectedPage, reduceMotion: reduceMotion)
    }

    var onboardingBackground: some View {
        CyberTheme.void
            .overlay(
                LinearGradient(
                    colors: [
                        CyberTheme.panel.opacity(0.72),
                        CyberTheme.void,
                        CyberTheme.void
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(CyberScanlines().opacity(0.07))
    }

    var currentPreset: CapturePreset {
        CapturePreset.preset(id: settings.selectedPresetID, settings: settings)
    }

    func setReplayGroup(_ group: OnboardingReplayGroup) {
        if reduceMotion {
            selectedReplayGroup = group
        } else {
            withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                selectedReplayGroup = group
            }
        }
    }

    func replayGroupValue(_ group: OnboardingReplayGroup) -> String {
        switch group {
        case .length:
            return OnboardingReadiness.bufferLabel(settings: settings)
        case .quality:
            return currentPreset.displayName
        case .hotkey:
            return settings.saveClipHotkey.compactDisplayValue
        case .storage:
            return OnboardingReadiness.saveLocationLabel(settings: settings)
        }
    }

    func replayGroupControls(_ group: OnboardingReplayGroup) -> AnyView {
        switch group {
        case .length:
            return AnyView(replayDurationControls)
        case .quality:
            return AnyView(qualityControls)
        case .hotkey:
            return AnyView(hotkeyControls)
        case .storage:
            return AnyView(saveLocationControls)
        }
    }

    var replayDurationControls: some View {
        OnboardingSegmentedControl(
            options: [30, 60, 120, 300].map { seconds in
                OnboardingSegmentedOption(id: "\(seconds)", title: durationChoiceLabel(seconds), value: seconds)
            },
            selection: settings.replayDurationSeconds,
            select: setReplayDuration
        )
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityLabel("Clip length")
        .accessibilityIdentifier("onboarding.replay.length.segmented")
    }

    var qualityControls: some View {
        OnboardingSegmentedControl(
            options: [CapturePreset.storageSaver, .balanced, .editing].map { preset in
                OnboardingSegmentedOption(id: preset.id, title: qualityChoiceLabel(preset), value: preset.id)
            },
            selection: settings.selectedPresetID,
            select: setSelectedPreset
        )
        .frame(maxWidth: 300, alignment: .leading)
        .accessibilityLabel("Quality")
        .accessibilityIdentifier("onboarding.replay.quality.segmented")
    }

    var hotkeyControls: some View {
        OnboardingSegmentedControl(
            options: SaveClipHotkey.choices.prefix(3).map { choice in
                OnboardingSegmentedOption(id: hotkeyIdentifier(choice), title: choice.compactDisplayValue, value: choice)
            },
            selection: settings.saveClipHotkey,
            select: setSaveClipHotkey
        )
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityLabel("Hotkey")
        .accessibilityIdentifier("onboarding.replay.hotkey.segmented")
    }

    var saveLocationControls: some View {
        HStack(spacing: 8) {
            Button("Pick Folder", action: chooseClipLibrary)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(CyberTheme.red)
                .accessibilityLabel("Pick save location")
                .accessibilityIdentifier("onboarding.replay.storage.pick")
                .help("Choose where saved clips are stored")
            Button("Use Default", action: resetClipLibrary)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Reset save location")
                .accessibilityIdentifier("onboarding.replay.storage.reset")
                .help("Use the default clip folder")
        }
    }

    func durationChoiceLabel(_ seconds: Int) -> String {
        switch seconds {
        case 30:
            return "30s"
        case 60:
            return "60s"
        case 120:
            return "2m"
        case 300:
            return "5m"
        default:
            return "\(seconds)s"
        }
    }

    func qualityChoiceLabel(_ preset: CapturePreset) -> String {
        switch preset.kind {
        case .storageSaver:
            return "Saver"
        case .balanced:
            return "Balanced"
        case .editing:
            return "Editing"
        case .custom:
            return "Custom"
        }
    }

    func hotkeyIdentifier(_ choice: SaveClipHotkey) -> String {
        ([choice.key] + choice.modifiers.map(\.rawValue)).joined(separator: "-")
    }
}

extension OnboardingView {
    var commandRailPrimaryTitle: String? {
        switch selectedPage {
        case .welcome:
            return "Get Started"
        case .ready:
            return nil
        case .access:
            return readiness.canEnterCapturely ? "Continue" : readiness.primaryTitle
        case .replay:
            return "Continue"
        }
    }
}

struct OnboardingHeroButton: View {
    enum Tone {
        case primary
        case secondary
    }

    var title: String
    var tone: Tone
    var accessibilityIdentifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.black).monospaced())
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(tone == .primary ? CyberTheme.text : CyberTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 24)
                .frame(minHeight: 44)
                .background(heroBackground(isPressed: false))
                .contentShape(CutCornerRectangle(cut: 9))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(title)
    }

    private func heroBackground(isPressed: Bool) -> some View {
        CutCornerRectangle(cut: 9)
            .fill(tone == .primary ? CyberTheme.red.opacity(isPressed ? 0.86 : 0.72) : CyberTheme.void.opacity(0.62))
            .overlay(
                CutCornerRectangle(cut: 9)
                    .stroke(tone == .primary ? CyberTheme.red.opacity(0.92) : CyberTheme.dim.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: tone == .primary ? CyberTheme.red.opacity(0.28) : .clear, radius: 12, x: 0, y: 0)
    }
}

private extension View {
    func onboardingReveal(isOnline: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(isOnline ? 1 : 0)
            .offset(y: reduceMotion || isOnline ? 0 : 10)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.38, extraBounce: 0).delay(Double(index) * 0.07),
                value: isOnline
            )
    }
}

struct OnboardingStepRail: View {
    var selectedPage: OnboardingPage
    var selectPage: (OnboardingPage) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases) { page in
                Button {
                    selectPage(page)
                } label: {
                    HStack(spacing: 8) {
                        Text(page.number)
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundStyle(isSelected(page) ? CyberTheme.red : CyberTheme.dim)
                            .lineLimit(1)
                        Text(page.rawValue.uppercased())
                            .font(.caption.weight(.heavy).monospaced())
                            .tracking(0.8)
                            .foregroundStyle(isSelected(page) ? CyberTheme.text : CyberTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(
                        CutCornerRectangle(cut: 9)
                            .fill(isSelected(page) ? CyberTheme.panelRaised : CyberTheme.panel.opacity(0.42))
                            .overlay(
                                CutCornerRectangle(cut: 9)
                                    .stroke(isSelected(page) ? CyberTheme.red.opacity(0.85) : CyberTheme.deepRed.opacity(0.38), lineWidth: 1)
                            )
                            .overlay(alignment: .bottomLeading) {
                                if isSelected(page) {
                                    Rectangle()
                                        .fill(CyberTheme.red)
                                        .frame(height: 3)
                                        .padding(.horizontal, 26)
                                }
                            }
                    )
                    .shadow(color: isSelected(page) ? CyberTheme.red.opacity(0.20) : .clear, radius: 12, x: 0, y: 0)
                }
                .buttonStyle(.plain)
                .contentShape(CutCornerRectangle(cut: 9))
                .accessibilityAddTraits(isSelected(page) ? .isSelected : [])
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(page.number) \(page.rawValue)")
                .accessibilityIdentifier("onboarding.step.\(page.rawValue.lowercased())")
                .help(page.title)
            }
        }
    }

    private func isSelected(_ page: OnboardingPage) -> Bool {
        selectedPage == page
    }
}

struct OnboardingAccessRow: View {
    var title: String
    var status: OnboardingReadiness.ItemStatus
    var systemImage: String
    var actionTitle: String?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(CyberTheme.red)
                .frame(width: 28)
            Text(title.uppercased())
                .font(.subheadline.weight(.heavy).monospaced())
                .tracking(0.7)
                .foregroundStyle(CyberTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(CyberTheme.deepRed)
                    .accessibilityLabel("\(actionTitle) \(title)")
                    .accessibilityIdentifier("onboarding.access.\(identifierSlug(title)).action")
                    .help(actionTitle)
            } else {
                OnboardingStatusChip(status: status)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(OnboardingCutPanel(isHot: status == .required))
    }

    private func identifierSlug(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

struct OnboardingReplayGroupPicker: View {
    var selectedGroup: OnboardingReplayGroup
    var selectGroup: (OnboardingReplayGroup) -> Void

    var body: some View {
        OnboardingSegmentedControl(
            options: OnboardingReplayGroup.allCases.map { group in
                OnboardingSegmentedOption(id: group.id, title: group.rawValue, value: group)
            },
            selection: selectedGroup,
            select: selectGroup
        )
        .frame(maxWidth: 380, alignment: .leading)
        .accessibilityLabel("Replay setup group")
        .accessibilityIdentifier("onboarding.replay.group.segmented")
        .help(selectedGroup.detail)
    }
}

struct OnboardingSegmentedOption<Value: Hashable>: Identifiable {
    var id: String
    var title: String
    var value: Value
}

struct OnboardingSegmentedControl<Value: Hashable>: View {
    var options: [OnboardingSegmentedOption<Value>]
    var selection: Value
    var select: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    select(option.value)
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.heavy).monospaced())
                        .foregroundStyle(isSelected(option) ? CyberTheme.text : CyberTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(segmentBackground(isSelected: isSelected(option)))
                .onTapGesture {
                    select(option.value)
                }
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected(option) ? .isSelected : [])

                if index < options.count - 1 {
                    Rectangle()
                        .fill(CyberTheme.deepRed.opacity(0.38))
                        .frame(width: 1, height: 18)
                }
            }
        }
        .padding(2)
        .background(
            CutCornerRectangle(cut: 7)
                .fill(CyberTheme.void.opacity(0.74))
                .overlay(
                    CutCornerRectangle(cut: 7)
                        .stroke(CyberTheme.deepRed.opacity(0.55), lineWidth: 1)
                )
        )
        .contentShape(CutCornerRectangle(cut: 7))
    }

    private func isSelected(_ option: OnboardingSegmentedOption<Value>) -> Bool {
        option.value == selection
    }

    private func segmentBackground(isSelected: Bool) -> some View {
        CutCornerRectangle(cut: 5)
            .fill(isSelected ? CyberTheme.red.opacity(0.82) : Color.clear)
            .overlay(
                CutCornerRectangle(cut: 5)
                    .stroke(isSelected ? CyberTheme.red.opacity(0.90) : Color.clear, lineWidth: 1)
            )
    }
}

struct OnboardingReplayGroupDetail: View {
    var group: OnboardingReplayGroup
    var value: String
    var controls: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: group.systemImage)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(CyberTheme.red)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(group.rawValue.uppercased())
                            .font(.caption.weight(.heavy).monospaced())
                            .tracking(0.7)
                            .foregroundStyle(CyberTheme.text)
                        Text(value)
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(CyberTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(group.detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(CyberTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            controls
        }
        .padding(10)
        .background(OnboardingCutPanel(isHot: true))
    }
}

struct OnboardingClipPreviewStack: View {
    var page: OnboardingPage
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            OnboardingClipCard(
                size: .large,
                timestamp: page == .ready ? "00:00:47" : "00:00:23",
                overlayTitle: page == .ready ? "VICTORY" : nil,
                overlaySubtitle: page == .ready ? "CLIP SAVED" : nil,
                accentIndex: pageIndex,
                reduceMotion: reduceMotion
            )
            HStack(spacing: 12) {
                OnboardingClipCard(size: .small, timestamp: "00:00:18", overlayTitle: nil, overlaySubtitle: nil, accentIndex: pageIndex + 1, reduceMotion: reduceMotion)
                OnboardingClipCard(size: .small, timestamp: "00:00:31", overlayTitle: nil, overlaySubtitle: nil, accentIndex: pageIndex + 2, reduceMotion: reduceMotion)
            }
        }
    }

    private var pageIndex: Int {
        OnboardingPage.allCases.firstIndex(of: page) ?? 0
    }
}

struct OnboardingClipCard: View {
    enum Size {
        case large
        case small
    }

    var size: Size
    var timestamp: String
    var overlayTitle: String?
    var overlaySubtitle: String?
    var accentIndex: Int
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            clipGradient
            CyberScanlines().opacity(0.08)
            if !reduceMotion {
                OnboardingClipScanLine()
                    .opacity(size == .large ? 0.22 : 0.12)
            }
            bracketOverlay
            VStack {
                HStack(alignment: .top) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(CyberTheme.red)
                            .frame(width: 7, height: 7)
                        Text("REC")
                            .font(.caption.weight(.black).monospaced())
                            .tracking(1.0)
                            .foregroundStyle(CyberTheme.red)
                    }
                    Spacer()
                    Text(timestamp)
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(CyberTheme.text)
                }
                Spacer()
                if let overlayTitle {
                    VStack(spacing: 4) {
                        Text(overlayTitle)
                            .font(.system(size: size == .large ? 42 : 20, weight: .black, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(CyberTheme.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.56)
                        if let overlaySubtitle {
                            Text(overlaySubtitle)
                                .font(.caption.weight(.heavy).monospaced())
                                .tracking(2.0)
                                .foregroundStyle(CyberTheme.text.opacity(0.86))
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, size == .large ? 18 : 6)
                }
                Spacer()
                HStack {
                    Image(systemName: "video")
                    Text("4K")
                    Spacer()
                    OnboardingSignalBars()
                }
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(CyberTheme.text.opacity(0.82))
            }
            .padding(size == .large ? 14 : 9)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size == .large ? 150 : 62)
        .clipShape(CutCornerRectangle(cut: size == .large ? 13 : 8))
        .overlay(
            CutCornerRectangle(cut: size == .large ? 13 : 8)
                .stroke(CyberTheme.red.opacity(size == .large ? 0.72 : 0.62), lineWidth: 1)
        )
        .shadow(color: CyberTheme.shadow.opacity(0.58), radius: 14, x: 0, y: 9)
    }

    private var clipGradient: some View {
        let palettes: [[Color]] = [
            [CyberTheme.void, CyberTheme.deepRed.opacity(0.78), Color(red: 0.02, green: 0.10, blue: 0.16)],
            [CyberTheme.void, Color(red: 0.12, green: 0.02, blue: 0.04), Color(red: 0.04, green: 0.10, blue: 0.16)],
            [Color(red: 0.02, green: 0.02, blue: 0.03), CyberTheme.red.opacity(0.44), Color(red: 0.01, green: 0.09, blue: 0.12)]
        ]
        return LinearGradient(
            colors: palettes[accentIndex % palettes.count],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [CyberTheme.red.opacity(0.38), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 220
            )
        )
    }

    private var bracketOverlay: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height) * 0.13
            ZStack {
                CornerBracket(corner: .topLeading, length: length)
                CornerBracket(corner: .topTrailing, length: length)
                CornerBracket(corner: .bottomLeading, length: length)
                CornerBracket(corner: .bottomTrailing, length: length)
            }
            .foregroundStyle(CyberTheme.text.opacity(0.42))
        }
    }
}

struct OnboardingClipScanLine: View {
    nonisolated static let usesContinuousAnimation = false

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, CyberTheme.red.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(proxy.size.width * 0.22, 42))
                .offset(x: proxy.size.width * 0.38)
        }
        .allowsHitTesting(false)
    }
}

struct OnboardingSignalBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(index < 4 ? CyberTheme.text.opacity(0.82) : CyberTheme.dim)
                    .frame(width: 3, height: CGFloat(5 + index * 3))
            }
        }
    }
}

struct CornerBracket: View {
    enum Corner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    var corner: Corner
    var length: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let inset: CGFloat = 10
                switch corner {
                case .topLeading:
                    path.move(to: CGPoint(x: inset, y: inset + length))
                    path.addLine(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: inset + length, y: inset))
                case .topTrailing:
                    path.move(to: CGPoint(x: proxy.size.width - inset - length, y: inset))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: inset))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: inset + length))
                case .bottomLeading:
                    path.move(to: CGPoint(x: inset, y: proxy.size.height - inset - length))
                    path.addLine(to: CGPoint(x: inset, y: proxy.size.height - inset))
                    path.addLine(to: CGPoint(x: inset + length, y: proxy.size.height - inset))
                case .bottomTrailing:
                    path.move(to: CGPoint(x: proxy.size.width - inset - length, y: proxy.size.height - inset))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: proxy.size.height - inset))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: proxy.size.height - inset - length))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .square, lineJoin: .miter))
        }
    }
}

struct OnboardingStatusChip: View {
    var status: OnboardingReadiness.ItemStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.black).monospaced())
            .tracking(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                CutCornerRectangle(cut: 5)
                    .fill(background)
                    .overlay(
                        CutCornerRectangle(cut: 5)
                            .stroke(foreground.opacity(0.70), lineWidth: 1)
                    )
            )
    }

    private var foreground: Color {
        switch status {
        case .required:
            return CyberTheme.warning
        case .ready, .armed:
            return CyberTheme.success
        case .optional, .later:
            return CyberTheme.muted
        }
    }

    private var background: Color {
        switch status {
        case .required:
            return CyberTheme.deepRed.opacity(0.52)
        case .ready, .armed:
            return CyberTheme.success.opacity(0.13)
        case .optional, .later:
            return CyberTheme.void.opacity(0.64)
        }
    }
}

struct OnboardingCutPanel: View {
    var isHot: Bool = false

    var body: some View {
        CutCornerRectangle(cut: 8)
            .fill(CyberTheme.void.opacity(isHot ? 0.62 : 0.48))
            .overlay(
                CutCornerRectangle(cut: 8)
                    .stroke((isHot ? CyberTheme.red : CyberTheme.deepRed).opacity(isHot ? 0.74 : 0.48), lineWidth: 1)
            )
            .background(
                CutCornerRectangle(cut: 8)
                    .fill(CyberTheme.deepRed.opacity(isHot ? 0.22 : 0.12))
                    .offset(x: 3, y: 3)
            )
    }
}

struct OnboardingCommandRail: View {
    var selectedPage: OnboardingPage
    var primaryTitle: String?
    var primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let primaryTitle {
                if selectedPage == .welcome {
                    OnboardingHeroButton(
                        title: primaryTitle,
                        tone: .primary,
                        accessibilityIdentifier: "onboarding.welcome.get-started",
                        action: primaryAction
                    )
                    .keyboardShortcut(.defaultAction)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(CyberTheme.red)
                        .font(.caption.weight(.heavy).monospaced())
                        .accessibilityIdentifier("onboarding.nav.primary")
                        .help(primaryTitle)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}
