import SwiftUI

/// Displays query history in a collapsible sidebar panel.
struct QueryHistoryView: View {
    @Environment(QueryViewModel.self) private var queryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(PostgraceTheme.accentSky)
                Text("Query History")
                    .font(.headline)
                Spacer()
                Text("\(queryViewModel.queryHistory.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .padding(8)

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            if queryViewModel.queryHistory.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No queries yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(PostgraceTheme.canvas)
            } else {
                List(queryViewModel.queryHistory.reversed()) { item in
                    QueryHistoryRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            queryViewModel.loadHistoryItem(item)
                        }
                        .contextMenu {
                            Button("Load Query") {
                                queryViewModel.loadHistoryItem(item)
                            }
                            Button("Copy Query") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.query, forType: .string)
                            }
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(PostgraceTheme.canvas)
            }
        }
        .background(PostgraceTheme.surface)
    }
}

/// A single query history row.
struct QueryHistoryRow: View {
    let item: QueryHistoryItem

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Query preview (first line, truncated)
            Text(item.query.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? item.query)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                // Timestamp
                Text(Self.timeFormatter.string(from: item.executedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Duration
                Text(String(format: "%.0fms", item.duration * 1000))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Row count
                Text("\(item.rowCount) rows")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
