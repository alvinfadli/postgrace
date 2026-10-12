import SwiftUI
import AppKit

/// Native macOS AppKit-backed SQL Editor view with real-time cursor/selection tracking,
/// intelligent shortcut dispatch (⌘↵ to execute current/selection, ⌘⇧↵ to execute all),
/// automated smart substitutions disabled (preventing broken SQL quotes/dashes),
/// line numbers gutter, and interactive IDE-style SQL autocompletion popup.
struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var selectedText: String
    var placeholder: String = "Type SQL queries here (separate with semicolons ;)..."
    var tables: [String: [TableInfo]] = [:]
    var columns: [String: [ColumnInfo]] = [:]
    var schemas: [SchemaInfo] = []
    var onExecuteCurrent: (() -> Void)? = nil
    var onExecuteAll: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = SQLCustomTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true

        // Disable macOS smart substitutions that corrupt SQL queries
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.delegate = context.coordinator
        textView.customCoordinator = context.coordinator
        textView.placeholderString = placeholder

        let completionController = SQLCompletionController()
        completionController.textView = textView
        textView.completionController = completionController

        scrollView.documentView = textView

        // Line Numbers Gutter
        let rulerView = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        rulerView.clientView = textView
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = true

        // Initial text
        if !text.isEmpty {
            textView.string = text
        }

        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.completionController = completionController
        context.coordinator.setupScrollObserver(scrollView: scrollView)

        DispatchQueue.main.async {
            rulerView.needsDisplay = true
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? SQLCustomTextView else { return }
        textView.placeholderString = placeholder

        if textView.string != text {
            let prevRange = textView.selectedRange()
            textView.string = text
            let safeLoc = min(prevRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
            context.coordinator.rulerView?.needsDisplay = true
        } else {
            context.coordinator.rulerView?.needsDisplay = true
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditorView
        weak var textView: SQLCustomTextView?
        weak var rulerView: LineNumberRulerView?
        var completionController: SQLCompletionController?
        private var observerToken: NSObjectProtocol?

        init(_ parent: SQLEditorView) {
            self.parent = parent
        }

        deinit {
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
            completionController?.dismiss()
        }

        func setupScrollObserver(scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            observerToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.rulerView?.needsDisplay = true
                self?.completionController?.dismiss()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            updateSelection(tv)
            rulerView?.needsDisplay = true

            // Trigger autocompletion evaluation
            completionController?.evaluateCompletions(
                tables: parent.tables,
                columns: parent.columns,
                schemas: parent.schemas
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            updateSelection(tv)
            rulerView?.needsDisplay = true
        }

        private func updateSelection(_ tv: NSTextView) {
            let range = tv.selectedRange()
            parent.selectedRange = range
            let nsString = tv.string as NSString
            if range.location + range.length <= nsString.length {
                parent.selectedText = nsString.substring(with: range)
            } else {
                parent.selectedText = ""
            }
        }
    }
}

// MARK: - Custom NSTextView with Shortcut Routing, Indentation & Autocomplete Key Handling

final class SQLCustomTextView: NSTextView {
    weak var customCoordinator: SQLEditorView.Coordinator?
    var completionController: SQLCompletionController?
    var placeholderString: String = ""

    override func keyDown(with event: NSEvent) {
        // 1. Check if completion popup is active
        if let cc = completionController, cc.isVisible {
            // Down Arrow (keyCode 125)
            if event.keyCode == 125 {
                cc.selectNext()
                return
            }
            // Up Arrow (keyCode 126)
            if event.keyCode == 126 {
                cc.selectPrevious()
                return
            }
            // Tab (48) or Return (36) while popup is active: confirm suggestion
            if (event.keyCode == 48 || event.keyCode == 36) && !event.modifierFlags.contains(.command) {
                cc.confirmSelection()
                return
            }
            // Escape (keyCode 53): close popup
            if event.keyCode == 53 {
                cc.dismiss()
                return
            }
        }

        // 2. Command + Return -> Execute
        if event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.charactersIgnoringModifiers == "\r") {
            completionController?.dismiss()
            if event.modifierFlags.contains(.shift) {
                customCoordinator?.parent.onExecuteAll?()
            } else {
                customCoordinator?.parent.onExecuteCurrent?()
            }
            return
        }

        // 3. Tab Key (keyCode 48) -> Insert 2 spaces
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                unindentSelection()
            } else {
                insertText("  ", replacementRange: selectedRange())
            }
            return
        }

        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        completionController?.dismiss()
        return super.resignFirstResponder()
    }

    private func unindentSelection() {
        let range = selectedRange()
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: range)
        let fullLine = nsString.substring(with: lineRange)

        if fullLine.hasPrefix("  ") {
            let newText = String(fullLine.dropFirst(2))
            if shouldChangeText(in: lineRange, replacementString: newText) {
                replaceCharacters(in: lineRange, with: newText)
                didChangeText()
            }
        } else if fullLine.hasPrefix(" ") {
            let newText = String(fullLine.dropFirst(1))
            if shouldChangeText(in: lineRange, replacementString: newText) {
                replaceCharacters(in: lineRange, with: newText)
                didChangeText()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder text when editor is empty
        if string.isEmpty && !placeholderString.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let origin = textContainerOrigin
            let rect = NSRect(x: origin.x + 5, y: origin.y + 1, width: bounds.width - origin.x - 10, height: bounds.height - origin.y)
            placeholderString.draw(in: rect, withAttributes: attributes)
        }
    }
}

// MARK: - Autocomplete Controller & Floating Popup

final class SQLCompletionController: ObservableObject {
    weak var textView: SQLCustomTextView?
    private var window: NSWindow?
    private var items: [SQLCompletionItem] = []
    private var selectedIndex: Int = 0
    private var replaceRange: NSRange = NSRange(location: 0, length: 0)
    private var evaluateTask: Task<Void, Never>?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func evaluateCompletions(
        tables: [String: [TableInfo]],
        columns: [String: [ColumnInfo]],
        schemas: [SchemaInfo]
    ) {
        evaluateTask?.cancel()
        evaluateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000) // 60ms debounce for rapid typing
            guard !Task.isCancelled, let self = self, let tv = self.textView else { return }
            let location = tv.selectedRange().location
            let text = tv.string

            let (prefix, range, suggestions) = SQLAutocompleteService.suggestions(
                for: text,
                at: location,
                tables: tables,
                columns: columns,
                schemas: schemas
            )

            guard !Task.isCancelled else { return }

            guard !suggestions.isEmpty && prefix.count >= 1 else {
                self.dismiss()
                return
            }

            self.items = suggestions
            self.replaceRange = range
            self.selectedIndex = 0
            self.showPopup()
        }
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
        updateWindowContent()
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        updateWindowContent()
    }

    func confirmSelection() {
        guard items.indices.contains(selectedIndex), let tv = textView else {
            dismiss()
            return
        }
        let item = items[selectedIndex]
        tv.insertText(item.insertText, replacementRange: replaceRange)
        dismiss()
    }

    func dismiss() {
        evaluateTask?.cancel()
        evaluateTask = nil
        window?.orderOut(nil)
        items = []
        selectedIndex = 0
    }

    private func showPopup() {
        guard let tv = textView, let textWindow = tv.window else { return }

        // Position directly at cursor character rect
        let charRect = tv.firstRect(forCharacterRange: NSRange(location: replaceRange.location, length: 0), actualRange: nil)

        let popupWidth: CGFloat = 280
        let popupHeight: CGFloat = min(CGFloat(items.count * 28 + 10), 190)

        // Screen coordinate placement
        var popupOrigin = NSPoint(x: charRect.minX, y: charRect.minY - popupHeight - 4)

        // If too close to bottom of screen, show above caret
        if let screen = textWindow.screen, popupOrigin.y < screen.visibleFrame.minY + 10 {
            popupOrigin.y = charRect.maxY + 4
        }

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(origin: popupOrigin, size: NSSize(width: popupWidth, height: popupHeight)),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.level = .popUpMenu
            win.isReleasedWhenClosed = false
            self.window = win
        }

        guard let win = window else { return }
        win.setFrame(NSRect(origin: popupOrigin, size: NSSize(width: popupWidth, height: popupHeight)), display: true)
        updateWindowContent()

        if !win.isVisible {
            win.orderFront(nil)
        }
    }

    private func updateWindowContent() {
        guard let win = window else { return }
        let rootView = SQLCompletionListView(
            items: items,
            selectedIndex: selectedIndex,
            onSelect: { [weak self] item in
                self?.textView?.insertText(item.insertText, replacementRange: self?.replaceRange ?? NSRange(location: 0, length: 0))
                self?.dismiss()
            }
        )
        win.contentView = NSHostingView(rootView: rootView)
    }
}

// MARK: - Autocomplete List View (SwiftUI)

struct SQLCompletionListView: View {
    let items: [SQLCompletionItem]
    let selectedIndex: Int
    let onSelect: (SQLCompletionItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isSelected = index == selectedIndex
                            HStack(spacing: 6) {
                                Image(systemName: item.kind.iconName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(iconColor(for: item.kind))
                                    .frame(width: 14)

                                Text(item.text)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? PostgraceTheme.accentSky : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(item)
                            }
                            .id(index)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(PostgraceTheme.surfaceElevated.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PostgraceTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }

    private func iconColor(for kind: SQLCompletionItem.Kind) -> Color {
        switch kind {
        case .keyword: return PostgraceTheme.accentSky
        case .table: return PostgraceTheme.emeraldRw
        case .column: return .orange
        case .function: return .purple
        case .clause: return .cyan
        case .snippet: return .secondary
        }
    }
}

// MARK: - Line Number Ruler View

final class LineNumberRulerView: NSRulerView {
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 34
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        ruleThickness = 34
        wantsLayer = true
        layer?.masksToBounds = true
    }

    private var cachedStringLength: Int = -1
    private var lineStarts: [Int] = [0]

    private func updateLineStartsIfNeeded(textString: NSString) {
        if textString.length == cachedStringLength {
            return
        }
        cachedStringLength = textString.length
        var starts: [Int] = [0]
        let len = textString.length
        for i in 0..<len {
            if textString.character(at: i) == 10 { // \n
                starts.append(i + 1)
            }
        }
        self.lineStarts = starts
    }

    private func lineNumber(for charIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= charIndex {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result + 1
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        // Background of gutter
        NSColor.windowBackgroundColor.withAlphaComponent(0.25).setFill()
        bounds.fill()

        // Border separator between gutter and text
        let borderRect = NSRect(x: bounds.maxX - 0.5, y: 0, width: 0.5, height: bounds.height)
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        borderRect.fill()

        let textString = textView.string as NSString
        guard textString.length > 0 else {
            // Draw line 1 when editor is completely empty
            let origin = convert(textView.textContainerOrigin, from: textView)
            drawLineNumber(1, at: origin.y + 1)
            return
        }

        updateLineStartsIfNeeded(textString: textString)

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let firstCharIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
        var lineNumber = lineNumber(for: min(firstCharIndex, textString.length))

        var glyphIndex = visibleGlyphRange.location
        let maxGlyphIndex = NSMaxRange(visibleGlyphRange)

        while glyphIndex < maxGlyphIndex {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = textString.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)

            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerOrigin.y

            let rulerY = convert(NSPoint(x: 0, y: lineRect.minY), from: textView).y
            drawLineNumber(lineNumber, at: rulerY + 1)

            lineNumber += 1
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        // Handle trailing newline extra line fragment (cursor on empty last line)
        if layoutManager.extraLineFragmentTextContainer != nil {
            var extraRect = layoutManager.extraLineFragmentRect
            extraRect.origin.y += textView.textContainerOrigin.y
            let rulerY = convert(NSPoint(x: 0, y: extraRect.minY), from: textView).y
            drawLineNumber(lineNumber, at: rulerY + 1)
        }
    }

    private func drawLineNumber(_ number: Int, at y: CGFloat) {
        let str = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6)
        ]
        let size = (str as NSString).size(withAttributes: attrs)
        let drawX = bounds.width - size.width - 8
        (str as NSString).draw(at: NSPoint(x: drawX, y: y), withAttributes: attrs)
    }
}
