import SwiftUI

/// Compact popover anchored to a table column header for configuring column-level filters.
public struct ColumnFilterPopoverView: View {
    let columnName: String
    let dataTypeName: String
    let currentRule: FilterRule?
    let onApply: (FilterOperator, String) -> Void
    let onClear: () -> Void

    @State private var selectedOp: FilterOperator = .equals
    @State private var filterValue: String = ""

    public init(
        columnName: String,
        dataTypeName: String = "",
        currentRule: FilterRule? = nil,
        onApply: @escaping (FilterOperator, String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.columnName = columnName
        self.dataTypeName = dataTypeName
        self.currentRule = currentRule
        self.onApply = onApply
        self.onClear = onClear
        _selectedOp = State(initialValue: currentRule?.op ?? .equals)
        _filterValue = State(initialValue: currentRule?.value ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Column Name and Type
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(PostgraceTheme.accentSky)

                Text(columnName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !dataTypeName.isEmpty && dataTypeName != "unknown" {
                    Text(dataTypeName.lowercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer(minLength: 0)
            }

            Divider()

            // Operator Selector Menu
            VStack(alignment: .leading, spacing: 4) {
                Text("CONDITION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                Menu {
                    ForEach(FilterOperator.allCases) { op in
                        Button {
                            selectedOp = op
                        } label: {
                            HStack {
                                Text(op.label)
                                if selectedOp == op {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedOp.label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(PostgraceTheme.accentSky)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            // Value Input (or no-value notice)
            if selectedOp.requiresValue {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VALUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    PostgraceTextField(
                        "Enter filter value…",
                        text: $filterValue,
                        isMonospaced: true
                    )
                    .onSubmit {
                        onApply(selectedOp, filterValue)
                    }
                }
            } else {
                Text("No input value needed for \(selectedOp.label)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                    .italic()
                    .padding(.vertical, 4)
            }

            // Quick Operator Shortcut Chips
            HStack(spacing: 5) {
                quickChip(label: "= Equals", op: .equals)
                quickChip(label: "Contains", op: .contains)
                quickChip(label: "IS NULL", op: .isNull)
                quickChip(label: "NOT NULL", op: .isNotNull)
            }
            .padding(.top, 2)

            Divider()

            // Footer Actions
            HStack(spacing: 8) {
                if currentRule != nil {
                    Button {
                        onClear()
                    } label: {
                        Text("Clear Filter")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PostgraceTheme.destructiveRed)
                    }
                    .buttonStyle(.plain)
                    .help("Remove active filter on \(columnName)")
                }

                Spacer()

                PostgraceButton(
                    "Apply",
                    icon: "checkmark",
                    variant: .primary,
                    size: .small
                ) {
                    onApply(selectedOp, filterValue)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(PostgraceTheme.surface)
    }

    @ViewBuilder
    private func quickChip(label: String, op: FilterOperator) -> some View {
        Button {
            selectedOp = op
        } label: {
            Text(label)
                .font(.system(size: 9, weight: selectedOp == op ? .bold : .regular))
                .foregroundColor(selectedOp == op ? PostgraceTheme.accentSky : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selectedOp == op ? PostgraceTheme.accentSkyMuted : PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
