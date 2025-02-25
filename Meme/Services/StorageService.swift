import Foundation
import FirebaseStorage
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "StorageService")

enum StorageError: Error {
    case imageConversionFailed
    case uploadFailed(Error)
    case urlRetrievalFailed
}

class StorageService {
    static let shared = StorageService()
    private let storage = Storage.storage()
    private let bucketName = "quacknews.appspot.com"  // Replace with your bucket name
    
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            logger.error("Failed to convert image to data")
            throw StorageError.imageConversionFailed
        }
        
        // Create the storage reference with explicit bucket
        let storageRef = storage.reference(forURL: "gs://\(bucketName)")
        let imageRef = storageRef.child("images/\(path)/\(UUID().uuidString).jpg")
        
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            _ = try await imageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await imageRef.downloadURL()
            
            logger.debug("Successfully uploaded image: \(downloadURL.absoluteString)")
            return downloadURL.absoluteString
        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")
            throw StorageError.uploadFailed(error)
        }
    }
    
    func getImageURL(path: String) async throws -> String {
        let storageRef = storage.reference(forURL: "gs://\(bucketName)")
        let imageRef = storageRef.child(path)
        
        do {
            let url = try await imageRef.downloadURL()
            return url.absoluteString
        } catch {
            logger.error("Failed to get URL: \(error.localizedDescription)")
            throw StorageError.urlRetrievalFailed
        }
    }
    
    // Helper method to list images in a directory
    func listImages(in directory: String) async throws -> [String] {
        let storageRef = storage.reference(forURL: "gs://\(bucketName)")
        let folderRef = storageRef.child(directory)
        
        do {
            let result = try await folderRef.listAll()
            var urls: [String] = []
            
            for item in result.items {
                let url = try await item.downloadURL()
                urls.append(url.absoluteString)
            }
            
            return urls
        } catch {
            logger.error("Failed to list images: \(error.localizedDescription)")
            throw StorageError.urlRetrievalFailed
        }
    }
    
    func getImageDownloadURL(filename: String = "IMG_3753.JPG") async throws -> String {
        let storageRef = storage.reference(forURL: "gs://\(bucketName)")
        let imageRef = storageRef.child(filename)
        
        do {
            let url = try await imageRef.downloadURL()
            logger.debug("Got download URL: \(url.absoluteString)")
            return url.absoluteString
        } catch {
            logger.error("Failed to get download URL: \(error.localizedDescription)")
            throw StorageError.urlRetrievalFailed
        }
    }
} 