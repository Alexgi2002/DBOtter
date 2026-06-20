# Design: SQL Editor Enhancement

## Technical Approach

Replace the basic `TextEditor` in `SQLQueryView` with Runestone's `TextView` (wrapped via `UIViewRepresentable`) to gain production-ready syntax highlighting. Layer custom autocompletion on top using Runestone's delegate system, fetching schema data from existing Go endpoints (`/tables`, `/table-structure`) with client-side caching.

This is an **additive change** — no existing code is removed, only wrapped and extended.

## Architecture Decisions

### Decision: Runestone as Editor Foundation

**Choice**: Runestone library (`simonbs/Runestone` v0.5.2+) with `TreeSitterLanguages` package for SQL grammar.

**Alternatives considered**:
- CodeMirror (Swift port) — less mature Swift integration, heavier dependency
- TextKit 2 directly — would require building syntax highlighting from scratch
- Monaco Editor (web view) — heavy, breaks native feel

**Rationale**: Runestone is purpose-built for this use case. It provides Tree-sitter-based syntax highlighting, line numbers, and a delegate system we can hook into for autocompletion. The `TreeSitterLanguages` package includes SQL grammar out of the box (`tree-sitter-sql`), so no grammar authoring needed. Active maintenance (v0.5.2 released March 2026).

### Decision: Client-Side Schema Caching

**Choice**: Cache table names and column metadata in-memory within a `SchemaCache` class, fetched once per connection and refreshed on-demand.

**Alternatives considered**:
- Server-side caching in Go backend — adds complexity, no benefit since data is small
- No caching — would make N network calls per autocomplete trigger
- UserDefaults persistence — overkill for session-scoped data

**Rationale**: Schema data is small (typically <100 tables, <1000 columns total). In-memory cache avoids network latency on every keystroke. Fetch-once-per-connection is sufficient since schema changes require explicit user action (refresh button already exists).

### Decision: Autocompletion Trigger Strategy

**Choice**: Trigger suggestions on:
1. Any alphabetic character (prefix matching against keywords + schema)
2. `.` separator (table.column completion)
3. After whitespace following SQL keywords (contextual hints)

**Alternatives considered**:
- Only trigger on `.` — too limited, misses keyword completion
- Trigger on every keystroke — wasteful, causes UI flicker
- Manual trigger (Ctrl+Space) — poor UX for discovery

**Rationale**: The proposal specifies "prefix matching, no fuzzy search." Triggering on alphabetic input gives immediate feedback. The `.` trigger is essential for `table.column` navigation. Debouncing (50-100ms) prevents excessive processing during rapid typing.

### Decision: SwiftUI Integration Pattern

**Choice**: Wrap Runestone's `TextView` in a `UIViewRepresentable` struct (`CodeEditorView`), with an `@Observable` view model (`CodeEditorViewModel`) managing state and autocompletion logic.

**Alternatives considered**:
- Direct UIKit integration — breaks SwiftUI view hierarchy
- NSViewRepresentable (macOS) — Runestone is iOS/UIKit-based, needs UIKit bridge
- Web-based editor — loses native performance

**Rationale**: `UIViewRepresentable` is the standard SwiftUI bridge for UIKit views. The view model pattern matches existing codebase conventions (`TableDataViewModel`, `TableStructureViewModel`). Using `@Observable` (Swift 5.9+) aligns with the project's Swift version.

## Data Flow

### Autocompletion Flow

```
User types in CodeEditorView
        │
        ▼
CodeEditorViewModel.textDidChange()
        │
        ├──► Debounce (50ms)
        │
        ▼
AnalyzeContext(text, cursorPosition)
        │
        ├──► Is after "."? → Fetch columns for table before dot
        │
        ├──► Is alphabetic? → Match against cached keywords + schema
        │
        ▼
FilterSuggestions(prefix, schema)
        │
        ▼
Update suggestions array
        │
        ▼
CodeEditorView shows suggestion popup (overlay)
        │
        ▼
User selects → Insert into text
```

### Schema Loading Flow

```
SQLQueryView appears
        │
        ▼
CodeEditorViewModel.init()
        │
        ▼
SchemaCache.shared.loadIfNeeded()
        │
        ├──► Cache hit? → Use cached data
        │
        ├──► Cache miss? → DatabaseService.fetchTables()
        │                    │
        │                    ▼
        │                  For each table: DatabaseService.fetchTableStructure()
        │                    │
        │                    ▼
        │                  Store in cache (table → [ColumnInfo])
        │
        ▼
Suggestions available for autocompletion
```

### Runestone Integration Flow

```
CodeEditorView (SwiftUI)
        │
        ▼
UIViewRepresentable
        │
        ├── makeUIView() → Create Runestone.TextView
        │                    Configure: theme, language (.sql), delegate
        │
        ├── updateUIView() → Sync text content
        │
        └── dismantleUIView() → Cleanup
                │
                ▼
        Runestone.TextView
                │
                ├── Tree-sitter SQL grammar (highlights)
                ├── TextViewDelegate → CodeEditorViewModel callbacks
                └── Custom overlay → Suggestion popup
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `macos-app/DBOtter/Views/CodeEditorView.swift` | **Create** | Runestone wrapper (`UIViewRepresentable`) with suggestion overlay |
| `macos-app/DBOtter/ViewModels/CodeEditorViewModel.swift` | **Create** | Editor state, autocompletion logic, context analysis |
| `macos-app/DBOtter/Services/SchemaCache.swift` | **Create** | In-memory cache for table/column metadata |
| `macos-app/DBOtter/Models/AutocompleteModels.swift` | **Create** | `AutocompleteSuggestion`, `EditorContext` types |
| `macos-app/DBOtter/Views/TableDataView.swift` | **Modify** | Replace `SQLQueryView` body to use `CodeEditorView` |
| `macos-app/DBOtter/Services/DatabaseService.swift` | **Modify** | Add `fetchAllSchemaData()` convenience method |
| `Package.swift` or Xcode project | **Modify** | Add Runestone + TreeSitterLanguages dependencies |

**Not modified** (unchanged):
- `GoEndpoints.swift` — no new endpoints needed (uses existing `/tables`, `/table-structure`)
- `handler.go` — no backend changes required
- `APIClient.swift` — existing client handles new requests

## Interfaces / Contracts

### New Types

```swift
// AutocompleteModels.swift

/// A single autocompletion suggestion
struct AutocompleteSuggestion: Identifiable, Hashable {
    let id = UUID()
    let text: String           // What gets inserted
    let displayText: String    // What's shown in popup
    let type: SuggestionType   // Icon/category
    let detail: String?        // Extra info (e.g., column type)
    
    enum SuggestionType {
        case keyword
        case table
        case column
        case function
    }
}

/// Context extracted from cursor position
struct EditorContext {
    let textBeforeCursor: String
    let currentWord: String
    let isAfterDot: Bool
    let tableBeforeDot: String?  // Table name if typing "table."
    let triggerType: TriggerType
    
    enum TriggerType {
        case prefix(String)      // Typing a word
        case dot(table: String)  // Just typed "."
        case none                // No trigger
    }
}
```

### SchemaCache Interface

```swift
// SchemaCache.swift

@MainActor
final class SchemaCache {
    static let shared = SchemaCache()
    
    /// Cached table names for current connection
    private(set) var tableNames: [String] = []
    
    /// Cached columns per table
    private(set) var columnsByTable: [String: [ColumnInfo]] = [:]
    
    /// Whether cache has been loaded for current session
    private(set) var isLoaded = false
    
    /// Load schema if not already cached
    func loadIfNeeded() async throws
    
    /// Force refresh (e.g., after DDL changes)
    func refresh() async throws
    
    /// Clear cache (on disconnect)
    func clear()
    
    /// Get columns for a specific table (returns empty if not cached)
    func columns(for table: String) -> [ColumnInfo]
    
    /// Get all column names across all tables
    func allColumnNames() -> [String]
}
```

### CodeEditorViewModel Interface

```swift
// CodeEditorViewModel.swift

@MainActor
@Observable
final class CodeEditorViewModel {
    /// Current editor text
    var text: String = ""
    
    /// Autocompletion suggestions to display
    var suggestions: [AutocompleteSuggestion] = []
    
    /// Whether suggestion popup is visible
    var showSuggestions = false
    
    /// Currently selected suggestion index
    var selectedIndex: Int = 0
    
    /// Loading state for initial schema fetch
    var isLoadingSchema = true
    
    /// Error message if schema fetch fails
    var errorMessage: String?
    
    /// Initialize with default query for table
    init(tableName: String)
    
    /// Called when text changes (debounced internally)
    func textDidChange(_ newText: String, cursorPosition: Int)
    
    /// Called when user selects a suggestion
    func acceptSuggestion(_ suggestion: AutocompleteSuggestion)
    
    /// Navigate suggestions with keyboard
    func moveSelection Up: Bool)
    
    /// Execute the current query
    func executeQuery() async throws -> QueryResult
    
    /// Get default query text
    var defaultQuery: String { get }
}
```

### CodeEditorView Interface

```swift
// CodeEditorView.swift

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage
    let theme: Theme
    let delegate: CodeEditorDelegate?
    
    /// Suggestions overlay (rendered in SwiftUI)
    var suggestions: [AutocompleteSuggestion]
    var showSuggestions: Bool
    var selectedIndex: Int
    var onSuggestionSelected: (AutocompleteSuggestion) -> Void
}

protocol CodeEditorDelegate: AnyObject {
    func codeEditorDidChangeText(_ editor: CodeEditorView, text: String, cursorPosition: Int)
    func codeEditorDidRequestExecution(_ editor: CodeEditorView)
}
```

## Caching Strategy

### Cache Structure

```swift
// In-memory cache — lives for the duration of the connection
final class SchemaCache {
    // Table names → quick lookup for prefix matching
    private var tableNames: Set<String> = []
    
    // Table name → columns → for dot-completion
    private var columnsByTable: [String: [ColumnInfo]] = [:]
    
    // Flattened column names → for global prefix matching
    private var allColumns: Set<String> = []
    
    // Timestamp of last fetch
    private var lastFetchTime: Date?
    
    // Cache validity: 5 minutes (schema changes are rare)
    private let cacheValidityDuration: TimeInterval = 300
}
```

### Cache Invalidation

1. **On disconnect**: `clear()` wipes everything
2. **On manual refresh**: User clicks refresh button → `refresh()` re-fetches
3. **Time-based**: Stale after 5 minutes (unlikely to matter in practice)
4. **On DDL execution**: If query executes successfully and looks like DDL (CREATE/ALTER/DROP), trigger `refresh()`

### Memory Impact

- 50 tables × 10 columns average = 500 `ColumnInfo` structs
- Each `ColumnInfo` ≈ 200 bytes estimated
- Total: ~100KB — negligible

## Performance Considerations

### Autocompletion Latency Target: <100ms

| Component | Budget | Strategy |
|-----------|--------|----------|
| Context analysis | <1ms | String operations, no allocations |
| Cache lookup | <1ms | Dictionary/Set O(1) lookups |
| Filtering | <5ms | Prefix matching on small dataset |
| UI update | <10ms | Diff-based suggestion list update |
| **Total** | **<20ms** | Well within 100ms budget |

### Debouncing

- Text change events debounced at 50ms
- Prevents excessive processing during rapid typing
- First suggestion appears after debounce settles

### Tree-sitter Performance

- Runestone uses incremental parsing — only re-parses changed lines
- SQL grammar is lightweight compared to full programming languages
- Syntax highlighting happens on background thread via Runestone internals

### Schema Loading

- First load: ~200ms (50 tables × 4ms per structure call, parallelized)
- Subsequent: instant (cache hit)
- Background loading: schema fetched async, editor appears immediately with empty suggestions

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | `EditorContext` parsing | Test cursor position → context extraction |
| Unit | `AutocompleteSuggestion` filtering | Test prefix matching logic |
| Unit | `SchemaCache` operations | Test load, cache hit, clear, refresh |
| Integration | Runestone wrapper | Verify text sync between SwiftUI and UIKit |
| Integration | Autocompletion end-to-end | Type in editor → suggestions appear → selection inserts |
| E2E | Full query workflow | Type query → execute → results display |
| E2E | Performance | Autocomplete response <100ms with 50+ tables |

## Migration / Rollout

**No migration required.** This is purely additive:
1. Add Runestone dependency to Xcode project
2. Create new files (CodeEditorView, ViewModel, Cache, Models)
3. Modify `SQLQueryView` to use `CodeEditorView` instead of `TextEditor`
4. Original `TextEditor` code is removed but preserved in git history

**Rollback**: Single commit revert restores previous `TextEditor` implementation.

## Open Questions

- [ ] **Runestone macOS compatibility**: Runestone was originally iOS-focused. Need to verify it compiles and works on macOS (macOS supports UIKit via Catalyst/UIViewRepresentable). If not, may need `NSViewRepresentable` with AppKit adaptation.
- [ ] **Theme selection**: Proposal says "use Runestone defaults." Should we allow user theme preference later? (Out of scope for now, but design should not prevent it.)
- [ ] **SQL dialect**: Runestone's tree-sitter-sql supports generic SQL. Different databases (PostgreSQL, MySQL, SQLite) have different keywords. Should we filter keywords based on connected engine? (Out of scope — use generic SQL keywords.)
