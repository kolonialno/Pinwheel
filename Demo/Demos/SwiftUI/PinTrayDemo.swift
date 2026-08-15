import SwiftUI
import Pinwheel

struct PinTrayDemo: View {
    private enum Route: Hashable {
        case boost
        case howItWorks
        case payWith
    }

    private struct Tier: Hashable {
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

    private let views = [
        Tier(reach: "8K – 15K views", price: "$50"),
        Tier(reach: "15K – 30K views", price: "$100"),
        Tier(reach: "30K – 80K views", price: "$250"),
        Tier(reach: "80K – 150K views", price: "$500"),
        Tier(reach: "150K – 300K views", price: "$1,000"),
    ]

    private let methods = [("applelogo", "Pay with Apple"), ("xmark.square", "Pay with X Money")]

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
                PinLabel("Get up to 3x more likes. Learn more")
                    .color(.secondary)
                    .padding(.vertical, .spacingXL)

                wheel(tiers, selected: selectedTier) { selectedTier = $0 }

                pill("Region", value: "United Kingdom") {}
                    .padding(.top, .spacingXL)
                pill("Pay with", value: methods[selectedMethod].1) { path.append(.payWith) }
                    .padding(.top, .spacingS)

                PinLabel("By clicking the Boost Post button below, you agree to our Terms and Conditions")
                    .font(.caption)
                    .color(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .spacingL)
                    .padding(.vertical, .spacingL)
            }
            .padding(.horizontal, .spacingL)
        } accessory: {
            Button { path.append(.howItWorks) } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.large)
            }
            .accessibilityLabel("How it works")
        }
        .commit("Boost Post") { path.removeAll() }
    }

    private var howItWorks: some View {
        PinTray("How it works") {
            VStack(spacing: 0) {
                wheel(views, selected: 2) { _ in }
                    .padding(.top, .spacingL)
                    .allowsHitTesting(false)

                PinLabel("Select your boost tier and watch your post go viral. Boosted posts will be labelled as boosted.")
                    .color(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .spacingL)
                    .padding(.vertical, .spacingXL)
            }
            .padding(.horizontal, .spacingL)
        }
        .commit("Got It") { path.removeLast() }
    }

    private var payWith: some View {
        PinTray("Pay with") {
            VStack(spacing: 0) {
                ForEach(Array(methods.enumerated()), id: \.offset) { index, method in
                    Button {
                        selectedMethod = index
                        path.removeLast()
                    } label: {
                        HStack(spacing: .spacingM) {
                            Image(systemName: method.0)
                                .imageScale(.large)
                                .frame(width: .spacingXXL)
                            PinLabel(method.1).font(.subtitleSemibold)
                            Spacer()
                            if index == selectedMethod {
                                Image(systemName: "checkmark")
                            }
                        }
                        .foregroundStyle(.primaryText)
                        .frame(minHeight: .minimumControlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pinwheel.tray.method.\(index)")
                }
            }
            .padding(.horizontal, .spacingL)
            .padding(.vertical, .spacingM)
        }
    }

    /// The reference shows five rows with the edges faded out, so the list reads as a wheel that
    /// runs past the tray rather than a list that ends there.
    private func wheel(_ rows: [Tier], selected: Int, select: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, tier in
                Button { select(index) } label: {
                    HStack {
                        PinLabel(tier.reach)
                            .color(index == selected ? .primary : .secondary)
                        Spacer()
                        PinLabel(tier.price)
                            .font(.subtitleSemibold)
                            .color(index == selected ? .primary : .secondary)
                    }
                    .padding(.horizontal, .spacingL)
                    .frame(minHeight: .minimumControlHeight)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: .radiusM)
                            .fill(index == selected ? Color.secondaryBackground : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func pill(_ title: String, value: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                PinLabel(title).color(.secondary)
                Spacer()
                PinLabel(value).font(.subtitleSemibold)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiaryText)
            }
            .padding(.horizontal, .spacingL)
            .frame(minHeight: .minimumControlHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: .radiusM)
                    .fill(Color.secondaryBackground)
            )
        }
        .buttonStyle(.plain)
    }
}
