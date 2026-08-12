import SwiftUI

struct PinwheelSettingsView: SwiftUI.View {
    let sections: [PinwheelSection]
    @SwiftUI.Binding var selectedSectionID: String?
    let tweaks: [PinwheelTweak]
    @SwiftUI.Binding var selectedDeviceIndex: Int?

    @Environment(PinwheelChrome.self) private var chrome
    @Environment(\.pinwheelTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some SwiftUI.View {
        NavigationStack {
            List {
                displayRows
                if !tweaks.isEmpty {
                    SwiftUI.Section {
                        ForEach(tweaks) { tweak in
                            tweakRow(tweak)
                                .listRowBackground(Color.primaryBackground)
                        }
                    } header: {
                        PinLabel("Options").font(.caption).color(.secondary).textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.primaryBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PinLabel("Settings").font(.subtitleSemibold)
                        .accessibilityIdentifier("pinwheel.settings.theme.\(theme.name)")
                }
            }
        }
    }

    @ViewBuilder
    private var displayRows: some SwiftUI.View {
        if sections.count > 1 {
            SettingsRow(title: "Section", value: selectedSection?.title ?? "") {
                sectionPicker
            }
            .accessibilityIdentifier("pinwheel.sectionPicker")
        }
        if chrome.themes.count > 1 {
            SettingsRow(title: "Theme", value: chrome.theme.name) {
                themePicker
            }
            .accessibilityIdentifier("pinwheel.theme")
        }
        SettingsRow(title: "Appearance", value: selectedAppearance.title) {
            appearancePicker
        }
        .accessibilityIdentifier("pinwheel.appearance")
        SettingsRow(title: "Device", value: simulatedDeviceTitle) {
            PinwheelDeviceList(selectedIndex: $selectedDeviceIndex)
        }
        .accessibilityIdentifier("pinwheel.device")
    }

    private var selectedSection: PinwheelSection? {
        sections.first { $0.id == selectedSectionID } ?? sections.first
    }

    private var selectedAppearance: PinwheelAppearance {
        PinwheelAppearance.allCases.first { $0.colorScheme == chrome.colorScheme } ?? .system
    }

    private var simulatedDeviceTitle: String {
        chrome.simulatedDevice?.title ?? "This device"
    }

    private var sectionPicker: some SwiftUI.View {
        PickerList(title: "Section") {
            ForEach(sections) { section in
                PickerRow(title: section.title, isSelected: section.id == selectedSection?.id) {
                    selectedSectionID = section.id
                    PinwheelStateStore.selectedSectionID = section.id
                    dismiss()
                }
                .listRowSeparatorTint(.secondaryBackground)
                .listRowBackground(Color.primaryBackground)
            }
        }
    }

    private var themePicker: some SwiftUI.View {
        PickerList(title: "Theme") {
            ForEach(chrome.themes) { theme in
                ThemeSampleRow(theme: theme, isSelected: theme == chrome.theme) {
                    chrome.selectTheme(theme)
                }
                .listRowSeparatorTint(.secondaryBackground)
                .listRowBackground(Color.primaryBackground)
            }
        }
    }

    private var appearancePicker: some SwiftUI.View {
        PickerList(title: "Appearance") {
            ForEach(PinwheelAppearance.allCases) { appearance in
                PickerRow(title: appearance.title, isSelected: appearance == selectedAppearance) {
                    chrome.colorScheme = appearance.colorScheme
                }
                .accessibilityIdentifier("pinwheel.appearance.\(appearance.rawValue)")
                .listRowSeparatorTint(.secondaryBackground)
                .listRowBackground(Color.primaryBackground)
            }
        }
    }

    @ViewBuilder
    private func tweakRow(_ tweak: PinwheelTweak) -> some SwiftUI.View {
        switch tweak.control {
        case .action(let action):
            SwiftUI.Button {
                action()
                dismiss()
            } label: {
                tweakLabels(tweak)
            }
            .buttonStyle(.plain)
        case .toggle(let isOn):
            Toggle(isOn: isOn) { tweakLabels(tweak) }
                .tint(.actionText)
        }
    }

    private func tweakLabels(_ tweak: PinwheelTweak) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            PinLabel(tweak.title)
            if let description = tweak.description {
                PinLabel(description).font(.caption).color(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsRow<Destination: SwiftUI.View>: SwiftUI.View {
    let title: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some SwiftUI.View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                PinLabel(title)
                Spacer()
                PinLabel(value).color(.secondary)
            }
        }
        .listRowSeparatorTint(.secondaryBackground)
        .listRowBackground(Color.primaryBackground)
    }
}

private struct PickerList<Content: SwiftUI.View>: SwiftUI.View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some SwiftUI.View {
        List(content: content)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.primaryBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PinLabel(title).font(.subtitleSemibold)
                }
            }
    }
}

enum PinwheelAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalizingFirstLetter }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct PickerRow: SwiftUI.View {
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some SwiftUI.View {
        SwiftUI.Button(action: select) {
            HStack {
                PinLabel(title).color(isSelected ? .action : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.actionText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ThemeSampleRow: SwiftUI.View {
    let theme: PinwheelTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some SwiftUI.View {
        PickerRow(title: theme.name, isSelected: isSelected, select: select)
            .environment(\.pinwheelTheme, theme)
            .accessibilityIdentifier("pinwheel.theme.\(theme.id)")
    }
}

struct PinwheelDeviceList: SwiftUI.View {
    @SwiftUI.Binding var selectedIndex: Int?

    private let devices = Device.all

    var body: some SwiftUI.View {
        PickerList(title: "Device") {
            ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                PickerRow(title: device.title, isSelected: isSelected(index, device)) {
                    selectedIndex = index
                }
                .disabled(!device.isEnabled)
                .listRowSeparatorTint(.secondaryBackground)
                .listRowBackground(Color.primaryBackground)
            }
        }
    }

    private func isSelected(_ index: Int, _ device: Device) -> Bool {
        if let selectedIndex { return selectedIndex == index }
        return device.isCurrent
    }
}
