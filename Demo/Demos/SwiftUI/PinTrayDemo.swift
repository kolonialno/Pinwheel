import SwiftUI
import Pinwheel

struct PinTrayDemo: View {
    private enum Route: Hashable {
        case boost
        case howItWorks
        case payWith
    }

    private struct Tier: Identifiable {
        let id = UUID()
        let reach: String
        let price: String
    }

    private let tiers = [
        Tier(reach: "692 – 1.1K impressions", price: "$1"),
        Tier(reach: "6.4K – 12K impressions", price: "$10"),
        Tier(reach: "15K – 30K impressions", price: "$25"),
        Tier(reach: "30K – 60K impressions", price: "$50"),
        Tier(reach: "60K – 119K impressions", price: "$100"),
    ]

    private let methods = ["Pay with Apple", "Pay with Card"]

    @State private var path: [Route] = []
    @State private var selectedTier = 2
    @State private var selectedMethod = 0

    var body: some View {
        VStack(spacing: .spacingL) {
            PinLabel("A tray sequence, each one as tall as its own content.")
                .color(.secondary)
                .multilineTextAlignment(.center)
            PinButton("Boost Post") { path = [.boost] }
                .style(.primary)
        }
        .padding(.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pinwheelTray(path: $path) { route in
            switch route {
            case .boost: boost
            case .howItWorks: howItWorks
            case .payWith: payWith
            }
        }
    }

    private var boost: some View {
        PinTray("Boost Post") {
            VStack(spacing: 0) {
                PinLabel("Get up to 3x more likes.")
                    .color(.secondary)
                    .padding(.bottom, .spacingM)
                ForEach(Array(tiers.enumerated()), id: \.element.id) { index, tier in
                    row(tier.reach, value: tier.price, isSelected: index == selectedTier) {
                        selectedTier = index
                    }
                }
                row("Pay with", value: methods[selectedMethod], isSelected: false) {
                    path.append(.payWith)
                }
                .padding(.top, .spacingM)
            }
            .padding(.horizontal, .spacingXL)
            .padding(.top, .spacingL)
        } accessory: {
            Button {
                path.append(.howItWorks)
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.large)
            }
            .accessibilityLabel("How it works")
        }
        .commit("Boost Post") { path.removeAll() }
    }

    private var howItWorks: some View {
        PinTray("How it works") {
            PinLabel("Select your boost tier and watch your post go viral. Boosted posts will be labelled as boosted.")
                .color(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .spacingXL)
                .padding(.top, .spacingXL)
        }
        .commit("Got It") { path.removeLast() }
    }

    private var payWith: some View {
        PinTray("Pay with") {
            VStack(spacing: 0) {
                ForEach(Array(methods.enumerated()), id: \.offset) { index, method in
                    row(method, value: index == selectedMethod ? "✓" : "", isSelected: false) {
                        selectedMethod = index
                        path.removeLast()
                    }
                }
            }
            .padding(.horizontal, .spacingXL)
            .padding(.top, .spacingL)
        }
    }

    private func row(
        _ title: String,
        value: String,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            HStack {
                PinLabel(title).color(isSelected ? .primary : .secondary)
                Spacer()
                PinLabel(value).font(.subtitleSemibold)
            }
            .padding(.horizontal, .spacingM)
            .frame(minHeight: .minimumControlHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: .radiusM)
                    .fill(isSelected ? Color.secondaryBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
