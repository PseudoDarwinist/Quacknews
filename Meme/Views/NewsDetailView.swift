import SwiftUI

struct NewsDetailView: View {
    let newsItem: NewsItem
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeme: Meme?
    @State private var isShowingFullScreenMeme = false
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var isRedditSource: Bool {
        return newsItem.redditURL.absoluteString.contains("reddit.com")
    }
    
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
                    .frame(height: 200)
                    .clipped()
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
                    
                    // Date information
                    Text("Published: \(formattedDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    // Only show the Reddit link if it's from Reddit and has a valid URL
                    if isRedditSource && newsItem.redditURL.absoluteString != "https://reddit.com" {
                        Link(destination: newsItem.redditURL) {
                            Label("View original source", systemImage: "link")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 2)
                    }
                    
                    if !newsItem.relatedMemes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Related Memes")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(newsItem.relatedMemes, id: \.id) { meme in
                                    MemeGridItem(meme: meme)
                                        .onTapGesture {
                                            selectedMeme = meme
                                            isShowingFullScreenMeme = true
                                        }
                                }
                            }
                        }
                    } else {
                        Text("No related memes available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("News Detail")
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
        .sheet(isPresented: $isShowingFullScreenMeme) {
            if let meme = selectedMeme {
                FullScreenMemeView(meme: meme)
            }
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: newsItem.publishedDate)
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

struct MemeGridItem: View {
    let meme: Meme
    
    var body: some View {
        VStack {
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
            .frame(height: 120)
            .cornerRadius(8)
            .clipped()
            
            if let title = meme.title {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

struct FullScreenMemeView: View {
    let meme: Meme
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    AsyncImage(url: meme.imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            scale = min(max(scale * delta, 1), 4)
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1 {
                                                offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                            
                                            // Reset position if scale is back to 1
                                            if scale <= 1 {
                                                withAnimation {
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation {
                                        if scale > 1 {
                                            scale = 1
                                            offset = .zero
                                            lastOffset = .zero
                                        } else {
                                            scale = 2
                                        }
                                    }
                                }
                        case .failure:
                            VStack {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                Text("Failed to load image")
                                    .foregroundColor(.white)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: meme.imageURL,
                        subject: Text(meme.title ?? "Shared Meme"),
                        message: Text("Check out this meme!")
                    )
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.6), for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
} 