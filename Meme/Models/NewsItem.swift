import Foundation

struct NewsItem: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let imageURL: URL?
    let category: NewsCategory
    let publishedDate: Date
    var relatedMemes: [Meme]
    let redditURL: URL
    
    enum NewsCategory: String, CaseIterable {
        case sports = "Sports"
        case elonMusk = "Elon Musk"
        case entertainment = "Entertainment"
        case ads = "Ads"
        case politics = "Politics"
    }
}

struct Meme: Identifiable {
    let id = UUID()
    let imageURL: URL
    let source: MemeSource
    let title: String?
    let redditURL: URL
    
    enum MemeSource {
        case reddit
        case manual
    }
}

// Sample Data
extension NewsItem {
    static var sampleNews: [NewsItem] = [
        NewsItem(
            title: "India vs Pakistan: Epic Semi-Final Showdown",
            summary: "In a thrilling match, India secured their place in the finals with a spectacular performance.",
            imageURL: URL(string: "https://example.com/cricket.jpg"),
            category: .sports,
            publishedDate: Date(),
            relatedMemes: [],
            redditURL: URL(string: "https://reddit.com/r/Cricket")!
        ),
        NewsItem(
            title: "SpaceX Starship Successfully Completes Orbital Test",
            summary: "Elon Musk's SpaceX achieves another milestone with successful Starship test flight.",
            imageURL: URL(string: "https://example.com/spacex.jpg"),
            category: .elonMusk,
            publishedDate: Date(),
            relatedMemes: [],
            redditURL: URL(string: "https://reddit.com/r/SpaceX")!
        )
    ]
} 