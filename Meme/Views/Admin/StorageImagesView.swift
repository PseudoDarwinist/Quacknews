import SwiftUI

struct StorageImagesView: View {
    @State private var imageURLs: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading images...")
            } else {
                ForEach(imageURLs, id: \.self) { url in
                    VStack(alignment: .leading) {
                        AsyncImage(url: URL(string: url)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(height: 200)
                        
                        Text(url)
                            .font(.caption)
                            .textSelection(.enabled)  // Makes the URL copyable
                    }
                }
            }
        }
        .navigationTitle("Stored Images")
        .task {
            await loadImages()
        }
        .refreshable {
            await loadImages()
        }
    }
    
    private func loadImages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            imageURLs = try await StorageService.shared.listImages(in: "images/news")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
} 