import SwiftUI

struct NewsDetailView: View {
    let newsItem: NewsItem
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    
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
                                    Link(destination: meme.redditURL) {
                                        MemeCell(meme: meme)
                                    }
                                    .buttonStyle(.plain)
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
        VStack(alignment: .leading) {
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            if let title = meme.title {
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
} 