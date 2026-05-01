import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseAuth

struct FavoritesListViewAlt: View {
    let onSelect: (CLLocationCoordinate2D) -> Void
    var currentCenter: CLLocationCoordinate2D?
    var userLocation: CLLocationCoordinate2D?

    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var favorites: [(id: String, name: String, coordinate: CLLocationCoordinate2D, rank: Int?)] = []
    @State private var addingName: String = ""
    @State private var addError: String? = nil

    private var userFavoritesCollection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("favorites")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading favorites…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") { fetchFavorites() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Add Favorite") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Name (e.g. Home, Office)", text: $addingName)
                                    .textFieldStyle(.roundedBorder)
                                if let addError { Text(addError).font(.footnote).foregroundStyle(.red) }
                                HStack {
                                    Button {
                                        if let coord = userLocation { addFavorite(name: addingNameOrFallback("My Location"), coordinate: coord) }
                                    } label: {
                                        Label("Add Current Location", systemImage: "location.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(userLocation == nil)
                                    Button {
                                        if let coord = currentCenter { addFavorite(name: addingNameOrFallback("Map Center"), coordinate: coord) }
                                    } label: {
                                        Label("Add Current View Center", systemImage: "viewfinder")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(currentCenter == nil)
                                }
                            }
                        }

                        Section("Your Favorites") {
                            if favorites.isEmpty {
                                Text("No favorites yet. Use the buttons above to add one.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(favorites, id: \ .id) { fav in
                                    Button(action: { onSelect(fav.coordinate) }) {
                                        HStack {
                                            Image(systemName: "mappin.and.ellipse")
                                            VStack(alignment: .leading) {
                                                Text(fav.name)
                                                if let rank = fav.rank { Text("Rank: \(rank)").font(.caption).foregroundStyle(.secondary) }
                                            }
                                        }
                                    }
                                }
                                .onDelete(perform: deleteFavorites)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .task { fetchFavorites() }
            .refreshable { fetchFavorites() }
        }
    }

    private func fetchFavorites() {
        guard let col = userFavoritesCollection else {
            self.errorMessage = "You must be signed in to view favorites."
            self.isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        col.order(by: "rank", descending: false).limit(to: 10).getDocuments { snap, err in
            if let err = err {
                // Fall back to ordering by name if rank missing
                (col.order(by: "name").limit(to: 10)).getDocuments { snap2, err2 in
                    self.handleSnapshot(snap2, err: err2)
                }
            } else {
                self.handleSnapshot(snap, err: nil)
            }
        }
    }

    private func handleSnapshot(_ snap: QuerySnapshot?, err: Error?) {
        if let err = err {
            self.errorMessage = "Failed to load favorites: \(err.localizedDescription)"
            self.favorites = []
            self.isLoading = false
            return
        }
        let items: [(String, String, CLLocationCoordinate2D, Int?)] = snap?.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String,
                  let lat = d["latitude"] as? CLLocationDegrees,
                  let lon = d["longitude"] as? CLLocationDegrees else { return nil }
            let rank = d["rank"] as? Int
            return (doc.documentID, name, CLLocationCoordinate2D(latitude: lat, longitude: lon), rank)
        } ?? []
        self.favorites = items.map { (id, name, coord, rank) in (id: id, name: name, coordinate: coord, rank: rank) }
        self.isLoading = false
    }

    private func addingNameOrFallback(_ fallback: String) -> String {
        let trimmed = addingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        guard let col = userFavoritesCollection else { return }
        addError = nil
        let data: [String: Any] = [
            "name": name,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "createdAt": FieldValue.serverTimestamp()
        ]
        col.addDocument(data: data) { err in
            if let err = err {
                self.addError = "Failed to add favorite: \(err.localizedDescription)"
            } else {
                self.addingName = ""
                fetchFavorites()
            }
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        guard let col = userFavoritesCollection else { return }
        let idsToDelete = offsets.map { favorites[$0].id }
        for id in idsToDelete {
            col.document(id).delete { _ in }
        }
        favorites.remove(atOffsets: offsets)
    }
}
