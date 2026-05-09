import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var filter: SearchFilter = .all
    @Published private(set) var result: SearchResult = .empty
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: YouTubeMusicClientProtocol
    private var searchTask: Task<Void, Never>?

    init(client: YouTubeMusicClientProtocol) {
        self.client = client
    }

    func queryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            result = .empty
            suggestions = []
            isLoading = false
            errorMessage = nil
            return
        }

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                await performSearch(query: trimmed)
            } catch {}
        }
    }

    func setFilter(_ newFilter: SearchFilter) {
        filter = newFilter
        queryChanged()
    }

    func submitSuggestion(_ suggestion: String) {
        query = suggestion
        queryChanged()
    }

    private func performSearch(query: String) async {
        isLoading = true
        errorMessage = nil
        async let suggestionsTask = client.getSuggestions(query: query)
        async let searchTask = client.search(query: query, filter: filter)
        do {
            let (suggestions, result) = try await (suggestionsTask, searchTask)
            self.suggestions = suggestions
            self.result = result
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

