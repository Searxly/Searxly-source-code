//
//  SearchQueryHistoryStore.swift
//  Searxly
//
//  Persists past search queries for re-surfacing them in address bar suggestions.
//  Stored in UserDefaults (not AppData.json) to avoid heavy read-modify-write on every keystroke.
//  Independent from the browsing URL history toggle — users can disable URL history but still
//  have search query suggestions, or vice versa.
//

import Foundation

struct SearchQueryRecord: Codable {
    let query: String
    let date: Date
}

final class SearchQueryHistoryStore {
    static let shared = SearchQueryHistoryStore()
    private init() {}

    private static let defaultsKey = "Searxly.SearchQueryHistory"
    private static let maxEntries = 200
    static let enabledKey = "searchQueryHistoryEnabled"

    // MARK: - Write

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 2 else { return }
        var entries = load()
        // Deduplicate case-insensitively; move existing match to front with fresh timestamp.
        entries.removeAll { $0.query.lowercased() == trimmed.lowercased() }
        entries.insert(SearchQueryRecord(query: trimmed, date: Date()), at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save(entries)
    }

    // MARK: - Query

    /// Returns past queries that start with `prefix`, most recent first, up to `max`.
    /// Excludes an exact case-insensitive match (the typed search row already covers that).
    func matching(_ prefix: String, max: Int = 5) -> [SearchQueryRecord] {
        let q = prefix.lowercased()
        guard !q.isEmpty else { return [] }
        return load()
            .filter { $0.query.lowercased().hasPrefix(q) && $0.query.lowercased() != q }
            .prefix(max)
            .map { $0 }
    }

    // MARK: - Clear

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Private

    private func load() -> [SearchQueryRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([SearchQueryRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private func save(_ entries: [SearchQueryRecord]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
