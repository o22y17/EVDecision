import MapKit
import SwiftUI

struct GooglePlaceAutocompleteView: View {
    @Binding var isPresented: Bool
    let onPlaceSelected: (SelectedPlace) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching && results.isEmpty {
                    ProgressView("Searching…")
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search for a destination",
                        systemImage: "magnifyingglass",
                        description: Text("Enter a place name or address.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results, id: \.self) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "Selected place")
                                    .foregroundStyle(.primary)
                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search")
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmedText

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }
            isSearching = false
        }
    }

    private func select(_ item: MKMapItem) {
        onPlaceSelected(
            SelectedPlace(
                name: item.name ?? item.placemark.title ?? "Selected place",
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
        )
        isPresented = false
    }
}
