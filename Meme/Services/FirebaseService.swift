import Foundation
import FirebaseFirestore
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "FirebaseService")

class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    
    private var newsCollection: CollectionReference {
        db.collection("news")
    }
    
    private var memesCollection: CollectionReference {
        db.collection("memes")
    }
    
    func fetchNews() async throws -> [NewsItem] {
        logger.info("Fetching news from Firebase")
        
        let newsSnapshot = try await newsCollection
            .order(by: "publishedDate", descending: true)
            .limit(to: 20)
            .getDocuments()
        
        var newsItems: [NewsItem] = []
        
        for document in newsSnapshot.documents {
            do {
                // Manual conversion from document data to NewsItem
                let data = document.data()
                let title = data["title"] as? String ?? ""
                let summary = data["summary"] as? String ?? ""
                let imageURLString = data["imageURL"] as? String ?? ""
                let categoryString = data["category"] as? String ?? "Sports"
                let timestamp = data["publishedDate"] as? Timestamp ?? Timestamp(date: Date())
                
                // Convert category string to NewsItem.NewsCategory
                let category = NewsItem.NewsCategory(rawValue: categoryString) ?? .sports
                
                // Fetch related memes
                let memesSnapshot = try await memesCollection
                    .whereField("newsId", isEqualTo: document.documentID)
                    .getDocuments()
                
                var memes: [Meme] = []
                for memeDoc in memesSnapshot.documents {
                    let memeData = memeDoc.data()
                    if let imageURL = memeData["imageURL"] as? String,
                       let url = URL(string: imageURL) {
                        memes.append(Meme(
                            imageURL: url,
                            source: .manual,
                            title: memeData["title"] as? String,
                            redditURL: URL(string: "https://reddit.com")!
                        ))
                    }
                }
                
                // Create NewsItem
                let newsItem = NewsItem(
                    title: title,
                    summary: summary,
                    imageURL: URL(string: imageURLString),
                    category: category,
                    publishedDate: timestamp.dateValue(),
                    relatedMemes: memes,
                    redditURL: URL(string: data["redditURL"] as? String ?? "https://reddit.com")!
                )
                
                newsItems.append(newsItem)
            } catch {
                logger.error("Error decoding news item: \(error.localizedDescription)")
                continue
            }
        }
        
        return newsItems
    }
} 
