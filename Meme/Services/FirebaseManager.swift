import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "FirebaseManager")

class FirebaseManager {
    static let shared = FirebaseManager()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {
        // Private initializer for singleton
    }
    
    // MARK: - News Operations
    func fetchNews(includeReddit: Bool = true) async throws -> [NewsItem] {
        do {
            logger.info("Fetching news from Firebase")
            
            // Get all documents from news collection
            let snapshot = try await db.collection("news").getDocuments()
            logger.info("Found \(snapshot.documents.count) documents in news collection")
            
            // Log document IDs for debugging
            let documentIDs = snapshot.documents.map { $0.documentID }
            if !documentIDs.isEmpty {
                logger.debug("Document IDs: \(documentIDs.joined(separator: ", "))")
            } else {
                logger.warning("No documents found in news collection")
                
                // If no Firebase content and Reddit is enabled, fetch from Reddit
                if includeReddit {
                    logger.info("No Firebase content, fetching from Reddit API")
                    return try await RedditService.shared.fetchNews()
                }
                
                return []
            }
            
            var newsItems: [NewsItem] = []
            
            for document in snapshot.documents {
                do {
                    let data = document.data()
                    let newsId = document.documentID
                    
                    // Log raw document data for debugging
                    logger.debug("Processing document \(newsId)")
                    
                    // Basic news data
                    let title = data["title"] as? String ?? "Untitled News"
                    let summary = data["summary"] as? String ?? "No summary available"
                    let imageURLString = data["imageURL"] as? String ?? ""
                    
                    // Handle category with special care
                    let categoryString = data["category"] as? String ?? "Sports"
                    logger.debug("Raw category string: '\(categoryString)'")
                    
                    // Ensure category string matches one of our enum cases exactly
                    var category: NewsItem.NewsCategory = .sports // Default
                    
                    // Try to match category string with enum cases (case-insensitive)
                    if let matchedCategory = NewsItem.NewsCategory.allCases.first(where: { 
                        $0.rawValue.lowercased() == categoryString.lowercased() 
                    }) {
                        category = matchedCategory
                        logger.debug("Matched category: \(category.rawValue)")
                    } else {
                        logger.warning("Could not match category string '\(categoryString)' to any known category, using default: \(category.rawValue)")
                    }
                    
                    // Safely create image URL
                    let imageURL = !imageURLString.isEmpty ? URL(string: imageURLString) : nil
                    
                    // Default empty memes array
                    var memes: [Meme] = []
                    
                    // Only try to create a default meme if we have an image URL
                    if let imageURL = imageURL {
                        // Create a default meme using the news image
                        memes = [
                            Meme(
                                imageURL: imageURL,
                                source: .manual,
                                title: title,
                                redditURL: URL(string: "https://reddit.com") ?? URL(string: "https://apple.com")!
                            )
                        ]
                    }
                    
                    // Try to fetch related memes
                    do {
                        let memesSnapshot = try await db.collection("memes")
                            .whereField("newsId", isEqualTo: newsId)
                            .getDocuments()
                        
                        logger.debug("Found \(memesSnapshot.documents.count) related memes for news \(newsId)")
                        
                        if !memesSnapshot.documents.isEmpty {
                            let relatedMemes = memesSnapshot.documents.compactMap { doc -> Meme? in
                                let memeData = doc.data()
                                guard let imageURLString = memeData["imageURL"] as? String,
                                      let imageURL = URL(string: imageURLString) else {
                                    return nil
                                }
                                
                                return Meme(
                                    imageURL: imageURL,
                                    source: .manual,
                                    title: memeData["title"] as? String,
                                    redditURL: URL(string: memeData["redditURL"] as? String ?? "https://reddit.com")!
                                )
                            }
                            
                            if !relatedMemes.isEmpty {
                                memes = relatedMemes
                                logger.debug("Using \(relatedMemes.count) related memes")
                            }
                        }
                    } catch {
                        logger.warning("Failed to fetch related memes: \(error.localizedDescription)")
                        // Continue with default meme
                    }
                    
                    // Safely create Reddit URL
                    let redditURLString = data["redditURL"] as? String ?? "https://reddit.com"
                    let redditURL = URL(string: redditURLString) ?? URL(string: "https://reddit.com")!
                    
                    // Get published date
                    let publishedDate: Date
                    if let timestamp = data["publishedDate"] as? Timestamp {
                        publishedDate = timestamp.dateValue()
                    } else {
                        publishedDate = Date()
                        logger.warning("No valid publishedDate found for document \(newsId), using current date")
                    }
                    
                    // Create news item with memes
                    let newsItem = NewsItem(
                        title: title,
                        summary: summary,
                        imageURL: imageURL,
                        category: category,
                        publishedDate: publishedDate,
                        relatedMemes: memes,
                        redditURL: redditURL
                    )
                    
                    newsItems.append(newsItem)
                    logger.debug("Added news item: \(title) with category: \(category.rawValue)")
                } catch {
                    logger.error("Error processing news document: \(error.localizedDescription)")
                    // Continue with next document
                    continue
                }
            }
            
            // If Reddit content is enabled, fetch and combine with Firebase content
            if includeReddit {
                do {
                    logger.info("Fetching additional news from Reddit API")
                    let redditNews = try await RedditService.shared.fetchNews()
                    
                    // Add Reddit news items, but avoid duplicates by title
                    let existingTitles = Set(newsItems.map { $0.title.lowercased() })
                    
                    for redditItem in redditNews {
                        if !existingTitles.contains(redditItem.title.lowercased()) {
                            newsItems.append(redditItem)
                            logger.debug("Added Reddit news item: \(redditItem.title)")
                        }
                    }
                    
                    logger.info("Added \(redditNews.count) news items from Reddit")
                } catch {
                    logger.warning("Failed to fetch Reddit news: \(error.localizedDescription)")
                    // Continue with Firebase content only
                }
            }
            
            // Sort by published date (newest first)
            newsItems.sort { $0.publishedDate > $1.publishedDate }
            
            // Log categories for debugging
            let categories = newsItems.map { $0.category.rawValue }
            let uniqueCategories = Set(categories)
            logger.info("News items by category: \(uniqueCategories.map { "\($0): \(categories.filter { $0 == $0 }.count)" }.joined(separator: ", "))")
            
            logger.info("Successfully fetched \(newsItems.count) total news items")
            return newsItems
        } catch {
            logger.error("Failed to fetch news: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Helper to fetch memes for a specific news item
    private func fetchMemesForNews(newsId: String) async throws -> [Meme] {
        // Try to get memes linked to this news item
        let memesSnapshot = try await db.collection("memes")
            .whereField("newsId", isEqualTo: newsId)
            .getDocuments()
        
        // Process memes if they exist
        let memes = memesSnapshot.documents.compactMap { doc -> Meme? in
            let data = doc.data()
            guard let imageURLString = data["imageURL"] as? String,
                  let imageURL = URL(string: imageURLString) else {
                return nil
            }
            
            return Meme(
                imageURL: imageURL,
                source: .manual,
                title: data["title"] as? String,
                redditURL: URL(string: data["redditURL"] as? String ?? "https://reddit.com")!
            )
        }
        
        return memes
    }
    
    // MARK: - Storage Operations
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            logger.error("Failed to convert image to data")
            throw NSError(domain: "FirebaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let ref = storage.reference().child("images/\(path)/\(filename)")
        
        do {
            logger.info("Uploading image to Firebase Storage")
            _ = try await ref.putDataAsync(imageData)
            let downloadURL = try await ref.downloadURL()
            logger.info("Image uploaded successfully: \(downloadURL.absoluteString)")
            return downloadURL.absoluteString
        } catch {
            logger.error("Failed to upload image: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Create News with Image
    func createNews(title: String, summary: String, imageURL: String, category: String) async throws {
        do {
            logger.info("Creating new news item: \(title) with category: \(category)")
            
            // Validate category
            let validCategory: String
            if NewsItem.NewsCategory.allCases.map({ $0.rawValue }).contains(category) {
                validCategory = category
            } else {
                logger.warning("Invalid category: \(category), defaulting to Sports")
                validCategory = "Sports"
            }
            
            let newsData: [String: Any] = [
                "title": title,
                "summary": summary,
                "imageURL": imageURL,
                "category": validCategory,
                "publishedDate": FieldValue.serverTimestamp(),
                "source": "manual",
                "redditURL": "https://reddit.com",
                "tags": []
            ]
            
            // Create news item
            let docRef = try await db.collection("news").addDocument(data: newsData)
            logger.debug("Created news document with ID: \(docRef.documentID)")
            
            // Create a meme using the same image
            let memeData: [String: Any] = [
                "imageURL": imageURL,
                "title": title,
                "source": "manual",
                "newsId": docRef.documentID,
                "category": validCategory,
                "redditURL": "https://reddit.com",
                "tags": []
            ]
            
            // Add meme linked to this news
            let memeRef = try await db.collection("memes").addDocument(data: memeData)
            logger.info("Successfully created news with meme. Meme ID: \(memeRef.documentID)")
        } catch {
            logger.error("Failed to create news: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Create Meme and Associate with News by Category
    func createMeme(title: String?, imageURL: String, category: String) async throws {
        do {
            logger.info("Creating new meme with category: \(category)")
            
            // First, get all news items with matching category
            let newsSnapshot = try await db.collection("news")
                .whereField("category", isEqualTo: category)
                .getDocuments()
            
            logger.info("Found \(newsSnapshot.documents.count) news items with category: \(category)")
            
            if newsSnapshot.documents.isEmpty {
                // If no matching news items, create a standalone meme
                let memeData: [String: Any] = [
                    "imageURL": imageURL,
                    "title": title ?? "",
                    "source": "manual",
                    "category": category,
                    "redditURL": "https://reddit.com",
                    "createdAt": FieldValue.serverTimestamp(),
                    "tags": []
                ]
                
                let memeRef = try await db.collection("memes").addDocument(data: memeData)
                logger.info("Created standalone meme with ID: \(memeRef.documentID)")
            } else {
                // Create a meme for each matching news item
                for newsDoc in newsSnapshot.documents {
                    let newsId = newsDoc.documentID
                    let newsTitle = newsDoc.data()["title"] as? String ?? "Unknown"
                    
                    let memeData: [String: Any] = [
                        "imageURL": imageURL,
                        "title": title ?? newsTitle,
                        "source": "manual",
                        "newsId": newsId,
                        "category": category,
                        "redditURL": "https://reddit.com",
                        "createdAt": FieldValue.serverTimestamp(),
                        "tags": []
                    ]
                    
                    let memeRef = try await db.collection("memes").addDocument(data: memeData)
                    logger.debug("Created meme with ID: \(memeRef.documentID) for news: \(newsTitle)")
                }
                
                logger.info("Successfully created memes for all matching news items")
            }
        } catch {
            logger.error("Failed to create meme: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Debug Helpers
    func listAllDocuments() async {
        do {
            logger.info("Listing all Firestore collections and documents")
            
            // Check news collection
            let newsSnapshot = try await db.collection("news").getDocuments()
            logger.info("Collection 'news' has \(newsSnapshot.documents.count) documents")
            
            for document in newsSnapshot.documents {
                logger.info("News Document ID: \(document.documentID)")
                let data = document.data()
                logger.debug("Title: \(data["title"] as? String ?? "Unknown")")
                logger.debug("Category: \(data["category"] as? String ?? "Unknown")")
            }
            
            // Check memes collection
            let memesSnapshot = try await db.collection("memes").getDocuments()
            logger.info("Collection 'memes' has \(memesSnapshot.documents.count) documents")
            
            for document in memesSnapshot.documents {
                logger.info("Meme Document ID: \(document.documentID)")
                let data = document.data()
                logger.debug("Title: \(data["title"] as? String ?? "Unknown")")
                logger.debug("NewsID: \(data["newsId"] as? String ?? "Unknown")")
            }
        } catch {
            logger.error("Failed to list documents: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Update Existing News Categories
    func updateNewsCategories() async {
        do {
            logger.info("Updating news categories in Firebase")
            
            // Get all documents from news collection
            let snapshot = try await db.collection("news").getDocuments()
            logger.info("Found \(snapshot.documents.count) documents to check for category updates")
            
            for document in snapshot.documents {
                let data = document.data()
                let newsId = document.documentID
                let title = data["title"] as? String ?? "Unknown"
                let currentCategory = data["category"] as? String ?? "Unknown"
                
                logger.debug("Checking news item: \(title), current category: \(currentCategory)")
                
                // Update categories based on title keywords
                var newCategory = currentCategory
                
                // Check title for category keywords
                let titleLower = title.lowercased()
                
                if titleLower.contains("cricket") || titleLower.contains("india vs pakistan") || 
                   titleLower.contains("epic") || titleLower.contains("showdown") {
                    newCategory = "Sports"
                } else if titleLower.contains("disney") || titleLower.contains("snow white") || 
                          titleLower.contains("movie") || titleLower.contains("film") {
                    newCategory = "Entertainment"
                } else if titleLower.contains("elon") || titleLower.contains("musk") || 
                          titleLower.contains("tesla") || titleLower.contains("spacex") {
                    newCategory = "Elon Musk"
                } else if titleLower.contains("ad") || titleLower.contains("commercial") || 
                          titleLower.contains("campaign") {
                    newCategory = "Ads"
                } else if titleLower.contains("politic") || titleLower.contains("government") || 
                          titleLower.contains("election") {
                    newCategory = "Politics"
                }
                
                // Only update if category changed
                if newCategory != currentCategory {
                    logger.info("Updating category for '\(title)' from '\(currentCategory)' to '\(newCategory)'")
                    
                    // Update the news document
                    try await db.collection("news").document(newsId).updateData([
                        "category": newCategory
                    ])
                    
                    // Also update any related memes
                    let memesSnapshot = try await db.collection("memes")
                        .whereField("newsId", isEqualTo: newsId)
                        .getDocuments()
                    
                    for memeDoc in memesSnapshot.documents {
                        try await db.collection("memes").document(memeDoc.documentID).updateData([
                            "category": newCategory
                        ])
                        logger.debug("Updated category for related meme: \(memeDoc.documentID)")
                    }
                    
                    logger.info("Successfully updated category for news item: \(title)")
                } else {
                    logger.debug("No category update needed for: \(title)")
                }
            }
            
            logger.info("Category update process completed")
        } catch {
            logger.error("Failed to update categories: \(error.localizedDescription)")
        }
    }
} 