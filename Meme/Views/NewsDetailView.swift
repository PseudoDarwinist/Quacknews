import SwiftUI

struct NewsDetailView: View {
    let newsItem: NewsItem
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeme: Meme?
    @State private var showingMemeDetail = false
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageURL = newsItem.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView())
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 250)
                    .clipShape(Rectangle())
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(newsItem.category.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(categoryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    Text(newsItem.title)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(newsItem.summary)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Link(destination: newsItem.redditURL) {
                        Label("Read on Reddit", systemImage: "link")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                    
                    if !newsItem.relatedMemes.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Related Memes")
                                .font(.headline)
                                .padding(.top)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(newsItem.relatedMemes) { meme in
                                    MemeCell(meme: meme)
                                        .onTapGesture {
                                            selectedMeme = meme
                                            showingMemeDetail = true
                                        }
                                }
                            }
                        }
                    } else {
                        Text("No memes available")
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(
                    item: newsItem.redditURL,
                    subject: Text(newsItem.title),
                    message: Text(newsItem.summary)
                )
            }
        }
        .sheet(isPresented: $showingMemeDetail, content: {
            if let meme = selectedMeme {
                MemeDetailView(meme: meme)
            }
        })
    }
    
    private var categoryColor: Color {
        switch newsItem.category {
        case .sports:
            return .blue
        case .elonMusk:
            return .purple
        case .entertainment:
            return .pink
        case .ads:
            return .green
        case .politics:
            return .red
        }
    }
}

struct MemeCell: View {
    let meme: Meme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: meme.imageURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
            
            if let title = meme.title {
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct MemeDetailView: View {
    let meme: Meme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    AsyncImage(url: meme.imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    if let title = meme.title {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: {
                        openURL(meme.redditURL)
                    }) {
                        Label("View on Reddit", systemImage: "link")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Meme")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareLink(
                        item: meme.imageURL,
                        subject: Text(meme.title ?? "Shared Meme"),
                        message: Text("Check out this meme!")
                    )
                }
            }
        }
    }
} 