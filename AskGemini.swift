import Foundation
import UIKit

/* ============================================================
   GENERATE IMAGE · for picture and drawing requests
   Replaces the Gemini Shortcuts hand-off (built 13/11, abandoned
   14/11/2026): that route switched the whole screen to Gemini's
   own app and Jarvis could never see or confirm what it actually
   showed. Groq's model (the real brain as of 14/11/2026 — see
   GroqBrain.swift) calls this as a function when a question needs
   a picture. Calls a free, keyless image API directly (Pollinations
   — plain HTTPS GET, no account, no billing) and returns the real
   image bytes, which JarvisEngine shows on Jarvis's own screen.
   ============================================================ */

enum ImageGen {
    /// Returns the raw image bytes on success, nil on any failure.
    static func run(description: String) async -> Data? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Alphanumerics only: the description becomes a URL PATH segment,
        // so even characters urlQueryAllowed/urlPathAllowed would let
        // through unescaped (/, ?, #) must still be encoded here, or they
        // would split the path instead of reaching Pollinations as text.
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://image.pollinations.ai/prompt/\(encoded)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
