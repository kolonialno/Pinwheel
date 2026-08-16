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

    private let tiers = [
        Tier(reach: "692 – 1.1K impressions", price: "$1"),
        Tier(reach: "6.4K – 12K impressions", price: "$10"),
        Tier(reach: "15K – 30K impressions", price: "$25"),
        Tier(reach: "30K – 60K impressions", price: "$50"),
        Tier(reach: "60K – 119K impressions", price: "$100"),
    ]

    private let methods = [
        (name: "Pay with Apple", icon: "apple.logo"),
        (name: "Pay with X Money", icon: "dollarsign.circle"),
    ]

    @State private var path: [Route] = []
    @State private var tier = 2
    @State private var tutorialStep = 0
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
            VStack(spacing: .spacingXL) {
                PinTrayLink("Get up to 3x more likes.", phrase: "Learn more") {}
                reach(selection: $tier)
                VStack(spacing: .spacingM) {
                    PinTrayValue("Region", value: region) { path.append(.region) }
                    PinTrayValue("Pay with", value: methods[method].name) { path.append(.payWith) }
                }
                PinTrayLink(
                    "By clicking the Boost Post button below, you agree to our",
                    phrase: "Terms and Conditions"
                ) {}
                .font(.footnote)
            }
            // Its first group stands off the chrome by what its groups stand off each other.
            .padding(.top, .spacingL)
        }
        .titleAccessory {
            SwiftUI.Button { path.append(.howItWorks) } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("How it works")
        }
        .commit("Boost Post") { path.removeAll() }
    }

    /// The tier the tutorial is showing. It walks up the tiers and back down rather than round, because
    /// wrapping from the last to the first is a jump backwards where every other step is a step.
    private var tutorialTier: Int {
        let last = tiers.count - 1
        let phase = tutorialStep % (last * 2)
        return phase <= last ? phase : last * 2 - phase
    }

    /// A wheel, as the reference has it: the tiers are a scale rather than a list, and the system picker
    /// already draws the banded selection this needs.
    private func reach(selection: Binding<Int>, travels: Bool = false) -> some View {
        TierWheel(tiers: tiers, selection: selection, travels: travels)
            .frame(height: 156)
        // The wheel insets its own selection band inside its frame, so it reaches back out by that much
        // to put the band on the same edge as its siblings.
        .padding(.horizontal, -.spacingS)
    }

    /// The tutorial: the same wheel, turning itself, over the sentence that says what it is for. It takes
    /// no input — a demonstration someone can grab stops demonstrating.
    private var howItWorks: PinTray {
        PinTray("How it works") {
            VStack(spacing: .spacingXL) {
                reach(selection: .constant(tutorialTier), travels: true)
                    .allowsHitTesting(false)
                PinTrayText(
                    "Select your boost tier and watch your post go viral. Boosted posts are labelled as boosted."
                )
                .centred()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.1))
                    withAnimation { tutorialStep += 1 }
                }
            }
        }
        .commit("Got It") { path.removeLast() }
    }

    private var payWith: PinTray {
        PinTray("Pay with") {
            VStack(spacing: .spacingXS) {
                ForEach(Array(methods.enumerated()), id: \.offset) { index, way in
                    PinTrayChoice(way.name, systemImage: way.icon, isChosen: index == method) {
                        method = index
                        path.removeLast()
                    }
                }
            }
        }
    }

    private var regions: PinTray {
        PinTray("Region") {
            VStack(spacing: .spacingXS) {
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
