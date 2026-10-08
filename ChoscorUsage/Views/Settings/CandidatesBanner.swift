// Offers discovered profiles for confirmation before they are added.
import ChoscorUsageKit
import SwiftUI

/// Lists discovery candidates with Add all and Dismiss actions.
struct CandidatesBanner: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found \(store.candidates.count) profile\(store.candidates.count == 1 ? "" : "s")")
                .font(.headline)
            ForEach(store.candidates, id: \.configDirectory) { candidate in
                Label {
                    Text(candidate.displayName)
                } icon: {
                    ProviderGlyph.image(for: candidate.provider)
                }
                .font(.callout)
            }
            HStack {
                Button("Add All") { store.add(store.candidates) }
                    .keyboardShortcut(.defaultAction)
                Button("Dismiss") { store.dismissCandidates() }
            }
        }
        .padding(12)
    }
}
