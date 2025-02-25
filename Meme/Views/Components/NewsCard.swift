import SwiftUI

struct NewsCard: View {
    let newsItem: NewsItem
    
    // Keep this property for internal use but don't display the badge
    private var isRedditSource: Bool {
        return newsItem.redditURL.absoluteString.contains("reddit.com")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category Badge (without source badge)
            Text(newsItem.category.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(categoryColor)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            // News Image
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Title and Summary
            VStack(alignment: .leading, spacing: 8) {
                Text(newsItem.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(formattedSummary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Time and Meme Count
                HStack {
                    Label(timeAgo, systemImage: "clock")
                    Spacer()
                    Label("\(newsItem.relatedMemes.count) memes", systemImage: "face.smiling")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private var formattedSummary: String {
        // Clean up the summary text for better display
        let summary = newsItem.summary
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If summary is too long, truncate it
        if summary.count > 120 {
            let endIndex = summary.index(summary.startIndex, offsetBy: min(120, summary.count))
            return String(summary[..<endIndex]) + "..."
        }
        return summary
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
    
    private var timeAgo: String {
        let interval = Calendar.current.dateComponents([.day, .hour, .minute], from: newsItem.publishedDate, to: Date())
        
        if let days = interval.day, days > 0 {
            return "\(days)d ago"
        } else if let hours = interval.hour, hours > 0 {
            return "\(hours)h ago"
        } else if let minutes = interval.minute, minutes > 0 {
            return "\(minutes)m ago"
        }
        return "Just now"
    }
}

#Preview {
    NewsCard(newsItem: NewsItem.sampleNews[0])
        .padding()
} 