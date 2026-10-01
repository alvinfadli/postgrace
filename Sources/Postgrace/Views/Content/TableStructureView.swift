import SwiftUI

/// Displays table structure: columns, types, constraints, and defaults in a pixel-accurate grid.
struct TableStructureView: View {
    @Environment(SchemaViewModel.self) private var schemaViewModel

    let schema: SchemaInfo
    let table: TableInfo

    // Exact column widths for alignment
    static let colWidthPK: CGFloat = 44
    static let colWidthName: CGFloat = 200
    static let colWidthType: CGFloat = 150
    static let colWidthSize: CGFloat = 90
    static let colWidthNullable: CGFloat = 100
    static let colWidthDefault: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(PostgraceTheme.accentSky)
                    .font(.system(size: 13, weight: .semibold))

                Text(table.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Text("/")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PostgraceTheme.border)

                Text(schema.name)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    Task {
                        await schemaViewModel.loadColumns(for: schema.name, table: table.name)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Refresh Columns")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PostgraceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .bottom
            )

            // Column List Grid
            let key = "\(schema.name).\(table.name)"
            if let cols = schemaViewModel.columns[key] {
                if cols.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tablecells.badge.ellipsis")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No columns found in '\(table.name)'")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PostgraceTheme.canvas)
                } else {
                    columnGrid(cols)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading columns structure…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PostgraceTheme.canvas)
                .task {
                    await schemaViewModel.loadColumns(for: schema.name, table: table.name)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PostgraceTheme.canvas)
    }

    // MARK: - Pixel-Aligned Column Grid

    @ViewBuilder
    private func columnGrid(_ columns: [ColumnInfo]) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(columns, id: \.id) { col in
                                    let isEven = col.ordinalPosition % 2 == 0
                                    TableStructureRowView(col: col, isEven: isEven, availableWidth: proxy.size.width)
                                }
                            } header: {
                                structureHeaderRow(availableWidth: proxy.size.width)
                            }
                        }
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                }
            }

            // Bottom Metrics Bar
            let pkCount = columns.filter(\.isPrimaryKey).count
            let nullableCount = columns.filter(\.isNullable).count
            HStack(spacing: 8) {
                Circle()
                    .fill(PostgraceTheme.emeraldRw)
                    .frame(width: 6, height: 6)
                Text("\(columns.count) columns")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)

                Text("•")
                    .foregroundColor(PostgraceTheme.border)

                Text("\(pkCount) primary key\(pkCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(pkCount > 0 ? .yellow : .secondary)

                Text("•")
                    .foregroundColor(PostgraceTheme.border)

                Text("\(nullableCount) nullable")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PostgraceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .top
            )
        }
    }

    // MARK: - Sticky Structure Header Row

    @ViewBuilder
    private func structureHeaderRow(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // # / PK Gutter
            Text("#")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthPK, height: 32, alignment: .center)
                .overlay(cellRightDivider, alignment: .trailing)

            // Column Name
            Text("COLUMN NAME")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthName, height: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(cellRightDivider, alignment: .trailing)

            // Data Type
            Text("DATA TYPE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthType, height: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(cellRightDivider, alignment: .trailing)

            // Nullable
            Text("NULLABLE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthNullable, height: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(cellRightDivider, alignment: .trailing)

            // Default Value
            Text("DEFAULT VALUE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthDefault, height: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(cellRightDivider, alignment: .trailing)

            // Max Length / Size
            Text("MAX LENGTH")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: Self.colWidthSize, height: 32, alignment: .leading)
                .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .frame(height: 32)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }

    private var cellRightDivider: some View {
        Rectangle()
            .fill(PostgraceTheme.border.opacity(0.6))
            .frame(width: PostgraceTheme.hairlineBorder)
    }
}

// MARK: - Decoupled Table Structure Row View (Localized Hover State)

struct TableStructureRowView: View {
    let col: ColumnInfo
    let isEven: Bool
    let availableWidth: CGFloat

    @State private var isHovered: Bool = false

    var body: some View {
        let zebraBg = isEven ? PostgraceTheme.canvas : PostgraceTheme.surface.opacity(0.35)
        let rowBg = isHovered ? PostgraceTheme.surfaceHover : zebraBg

        HStack(spacing: 0) {
            // Column # / PK Gutter
            HStack(spacing: 2) {
                if col.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
                Text("\(col.ordinalPosition)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(col.isPrimaryKey ? .yellow : .secondary)
            }
            .frame(width: TableStructureView.colWidthPK, height: 28, alignment: .center)
            .overlay(cellRightDivider, alignment: .trailing)

            // Column Name
            HStack(spacing: 4) {
                Text(col.name)
                    .font(.system(size: 12, weight: col.isPrimaryKey ? .bold : .medium, design: .monospaced))
                    .foregroundColor(.primary)
                if col.isPrimaryKey {
                    Text("PK")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.15))
                        .foregroundColor(.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: TableStructureView.colWidthName, height: 28, alignment: .leading)
            .padding(.horizontal, 10)
            .overlay(cellRightDivider, alignment: .trailing)

            // Data Type
            Text(col.dataType)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(PostgraceTheme.accentSky)
                .frame(width: TableStructureView.colWidthType, height: 28, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(cellRightDivider, alignment: .trailing)

            // Nullable
            HStack {
                if col.isNullable {
                    Text("NULL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("NOT NULL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PostgraceTheme.amberRo)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PostgraceTheme.amberRoMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: TableStructureView.colWidthNullable, height: 28, alignment: .leading)
            .padding(.horizontal, 10)
            .overlay(cellRightDivider, alignment: .trailing)

            // Default Value
            Group {
                if let def = col.defaultValue {
                    Text(def)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(PostgraceTheme.border)
                }
            }
            .frame(width: TableStructureView.colWidthDefault, height: 28, alignment: .leading)
            .padding(.horizontal, 10)
            .overlay(cellRightDivider, alignment: .trailing)

            // Max Length
            Group {
                if let maxLen = col.characterMaxLength {
                    Text("\(maxLen)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(PostgraceTheme.border)
                }
            }
            .frame(width: TableStructureView.colWidthSize, height: 28, alignment: .leading)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .frame(height: 28)
        .background(rowBg)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border.opacity(0.4))
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var cellRightDivider: some View {
        Rectangle()
            .fill(PostgraceTheme.border.opacity(0.6))
            .frame(width: PostgraceTheme.hairlineBorder)
    }
}
