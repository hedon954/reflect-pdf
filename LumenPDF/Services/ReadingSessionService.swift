import Foundation
import CryptoKit

/// Lightweight utilities for reading session management (pure Swift, no Rust calls).
final class ReadingSessionService: ObservableObject {

    /// Compute SHA-256 hash of the sentence (matches the Rust side's `sentence_hash`).
    func sentenceHash(_ sentence: String) -> String {
        let data = Data(sentence.lowercased().utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
