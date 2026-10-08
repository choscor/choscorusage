// The menu bar popover: candidate banner, one section per visible profile, and the footer.
import ChoscorUsageKit
import SwiftUI

/// Lists visible profiles in user order; refreshes stale data when opened.
struct PopoverView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.candidates.isEmpty {
                CandidatesBanner(store: store)
                Divider()
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ProfileSections(usages: store.visibleUsages, now: context.date, store: store)
            }
            Divider()
            PopoverFooter(store: store)
        }
        .frame(width: 320)
        .task { await store.refresh(.popoverOpened) }
    }
}

/// The scrollable profile sections, or an empty state.
private struct ProfileSections: View {
    let usages: [ProfileUsage]
    let now: Date
    let store: UsageStore

    var body: some View {
        if usages.isEmpty {
            EmptyProfilesView(store: store)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(usages) { usage in
                        ProfileSectionView(usage: usage, now: now) {
                            Task { await store.retry(usage.id) }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown when no visible profile exists.
private struct EmptyProfilesView: View {
    let store: UsageStore

    var body: some View {
        VStack(spacing: 8) {
            Text("No profiles yet")
                .font(.headline)
            Button("Scan for Claude and Codex profiles") {
                Task { await store.rescan() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
