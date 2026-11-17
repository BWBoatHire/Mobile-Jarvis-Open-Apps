import Foundation
import Security

/* ============================================================
   WEB SEARCH · for questions the notes can't answer
   Groq's model (the real brain as of 14/11/2026 — see GroqBrain.swift)
   decides when it needs the web (news, sport, prices, local
   businesses) and calls this as a function. Asks Tavily (free plan:
   1,000 searches a month, one per question), trims the results to a
   short digest, and hands them back for the model to answer from in
   its own words.
   Only the search query leaves the iPad. The Tavily key lives in
   this iPad's keychain, never in notes or code.
   ============================================================ */

enum SearchKey {
    private static let service = "Jarvis.TavilyKey"
    private static let account = "tavily"

    static var isSet: Bool { load() != nil }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

enum WebSearch {
    /// Returns the spoken digest AND the real result URLs, separately —
    /// the digest (sent to Groq) never contains a raw address, but
    /// open_webpage needs the real ones to check against, so a request
    /// to actually SHOW a page can never be satisfied by a URL the model
    /// just invented from memory (14/11/2026, backlog #36).
    static func run(query: String) async -> (text: String, urls: [String]) {
        guard let key = SearchKey.load() else {
            return ("Web search isn't set up yet: there's no search key on this iPad. Tell Carl to add one with the search key button.", [])
        }
        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": query,
            "search_depth": "basic",     // one credit per search
            "max_results": 4,
            "include_answer": "basic",
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return ("Couldn't build the search request.", [])
        }
        request.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return (explain(status), []) }
            return digest(data, query: query)
        } catch {
            return ("The web search didn't go through. The iPad may be offline.", [])
        }
    }

    /// REAL photos — distinct from ImageGen, which only fabricates
    /// pictures. Tavily's `include_images` returns genuine image URLs
    /// scraped from real web pages during the search, same key, no extra
    /// cost over a normal search (14/11/2026 — "get me/find me/are there
    /// pictures of X" needs real retrieval, not generation).
    static func findPhotos(query: String) async -> (text: String, images: [Data]) {
        guard let key = SearchKey.load() else {
            return ("Web search isn't set up yet: there's no search key on this iPad.", [])
        }
        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": query,
            "search_depth": "basic",
            "max_results": 4,
            "include_images": true,
            "include_image_descriptions": true,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return ("Couldn't build the photo search request.", [])
        }
        request.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return (explain(status), []) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let imageEntries = json["images"] as? [[String: Any]], !imageEntries.isEmpty else {
                return ("No real photos of that were found.", [])
            }
            var images: [Data] = []
            for entry in imageEntries.prefix(4) {
                guard let urlString = entry["url"] as? String, let url = URL(string: urlString),
                      let (imgData, imgResponse) = try? await URLSession.shared.data(from: url),
                      let http = imgResponse as? HTTPURLResponse, http.statusCode == 200, !imgData.isEmpty else { continue }
                images.append(imgData)
            }
            guard !images.isEmpty else { return ("Photos were found but couldn't be downloaded.", []) }
            return ("\(images.count) real photo(s) of \"\(query)\" are now showing on Carl's own screen.", images)
        } catch {
            return ("The photo search didn't go through. The iPad may be offline.", [])
        }
    }

    private static func explain(_ status: Int) -> String {
        switch status {
        case 401: return "The search service rejected the key. Tell Carl to check his Tavily key."
        case 429, 432, 433: return "The free search allowance is used up for now."
        default: return "The search service had a problem (code \(status)). Try again shortly."
        }
    }

    // Small enough for the model's memory: the quick answer plus four
    // short snippets, each with the site it came from (no web addresses
    // in the text itself — the real ones come back separately below).
    private static func digest(_ data: Data, query: String) -> (text: String, urls: [String]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("The search came back in a form I couldn't read.", [])
        }
        var out = "Web results for: \(query)\n"
        if let answer = json["answer"] as? String, !answer.isEmpty {
            out += "Summary: \(answer.prefix(500))\n"
        }
        let results = json["results"] as? [[String: Any]] ?? []
        var urls: [String] = []
        for (i, r) in results.prefix(4).enumerated() {
            let title = r["title"] as? String ?? ""
            let content = (r["content"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
            let urlString = r["url"] as? String ?? ""
            let site = URL(string: urlString)?.host() ?? "unknown site"
            out += "\(i + 1). \(title) (\(site)): \(content.prefix(350))\n"
            if !urlString.isEmpty { urls.append(urlString) }
        }
        if results.isEmpty && json["answer"] == nil { out += "Nothing useful was found." }
        return (out, urls)
    }
}
