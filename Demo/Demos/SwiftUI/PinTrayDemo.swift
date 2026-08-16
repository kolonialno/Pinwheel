import SwiftUI
import Pinwheel

/// Boost Post, mocked: a flow of four trays built from data the screen already holds.
struct PinTrayDemo: View {
    private enum Route: Hashable {
        case boost
        case howItWorks
        case payWith
        case region
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

    private let methods = ["Pay with Apple", "Pay with X Money"]

    @State private var path: [Route] = []
    @State private var tier = 2
    @State private var method = 0
    @State private var region = "United Kingdom"
    @State private var query = ""

    var body: some View {
        VStack(spacing: .spacingL) {
            PinLabel("A tray sequence, each one as tall as its own content.")
                .color(.secondary)
                .multilineTextAlignment(.center)
            PinButton("Boost Post") { path = [.boost] }
        }
        .padding(.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pinwheelTray(path: $path) { route in
            switch route {
            case .boost: boost
            case .howItWorks: howItWorks
            case .payWith: payWith
            case .region: regions
            }
        }
    }

    private var boost: PinTray {
        PinTray("Boost Post") {
            VStack(spacing: 0) {
                PinTrayLink("Get up to 3x more likes.", phrase: "Learn more") {}
                ForEach(Array(tiers.enumerated()), id: \.offset) { index, offer in
                    PinTrayChoice(offer.reach, detail: offer.price, isChosen: index == tier) {
                        tier = index
                    }
                }
                PinTrayValue("Region", value: region) { path.append(.region) }
                PinTrayValue("Pay with", value: methods[method]) { path.append(.payWith) }
                PinTrayText("By clicking Boost Post below you agree to our Terms and Conditions.")
                    .centred()
            }
        }
        .titleAccessory {
            SwiftUI.Button { path.append(.howItWorks) } label: {
                Image(systemName: "questionmark.circle").imageScale(.large)
            }
            .accessibilityLabel("How it works")
        }
        .commit("Boost Post") { path.removeAll() }
    }

    private var howItWorks: PinTray {
        PinTray("How it works") {
            PinTrayText(
                "Select your boost tier and watch your post go viral. Boosted posts are labelled as boosted."
            )
        }
    }

    private var payWith: PinTray {
        PinTray("Pay with") {
            VStack(spacing: 0) {
                ForEach(Array(methods.enumerated()), id: \.offset) { index, name in
                    PinTrayChoice(name, isChosen: index == method) {
                        method = index
                        path.removeLast()
                    }
                }
            }
        }
    }

    private var regions: PinTray {
        PinTray("Region") {
            VStack(spacing: 0) {
                if matches.isEmpty {
                    PinTrayText("No regions match “\(query)”").centred()
                } else {
                    ForEach(matches, id: \.self) { name in
                        PinTrayChoice(name, isChosen: name == region) {
                            region = name
                            path.removeLast()
                        }
                        .accessibilityIdentifier("pinwheel.tray.country.\(name)")
                    }
                }
            }
        }
        .detent(.filling)
        .floating { PinTraySearchField("Search Country, City, or Region", text: $query) }
    }

    /// Ranked so a typed prefix wins.
    private var matches: [String] {
        guard !query.isEmpty else { return Self.countries }
        let needle = query.lowercased()
        return Self.countries
            .filter { $0.lowercased().contains(needle) }
            .sorted { first, second in
                let firstStarts = first.lowercased().hasPrefix(needle)
                let secondStarts = second.lowercased().hasPrefix(needle)
                return firstStarts == secondStarts ? first < second : firstStarts
            }
    }

    // A region's own subRegions are its states, so those cannot filter it out.
    private static let countries: [String] = Locale.Region.isoRegions
        .filter { $0.subRegions.isEmpty }
        .compactMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
        .sorted()
}
