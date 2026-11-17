import Foundation
import Security

/* ============================================================
   GROQ BRAIN · the one real brain, replacing the on-device router
   (14/11/2026, Carl's call: "stop dodging the scope... deliver an
   intelligent AI model that does what I ask via the Jarvis
   interface.")

   Until today, Apple's small on-device model decided WHETHER to
   use searchWeb/generateImage/consultCloudAI — so a weak router
   gave weak results even with good tools behind it ("aerial shots
   of Atherton" got refused outright). Now the ENTIRE conversation
   goes straight to Groq's much larger model (openai/gpt-oss-120b,
   the same one already running the laptop's Coding Brain, with
   real function-calling already proven there). It decides itself,
   every time, whether to answer from Carl's own notes (already in
   its system prompt, same as before), search the web, draw a
   picture, or just answer from its own knowledge — no small local
   model pre-filtering the decision.
   Only the conversation leaves the iPad. The Groq key lives in this
   iPad's keychain, never in notes or code.
   ============================================================ */

enum CloudAIKey {
    private static let service = "Jarvis.GroqKey"
    private static let account = "groq"

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

@MainActor
enum GroqBrain {
    /// The two things the model can actually do beyond talking — OpenAI-
    /// style function schemas, since Groq's API doesn't know Apple's
    /// @Generable/Tool machinery at all.
    static let toolsSchema: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "search_web",
                "description": "Search the internet for current or local information: news, sport results, prices, local businesses, or any fact that may have changed. Not for questions about Carl's own notes.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "A short, specific web search query. Include the year for recent events and the town for local questions."]
                    ],
                    "required": ["query"],
                ],
            ],
        ],
        [
            "type": "function",
            "function": [
                "name": "generate_image",
                "description": "Create a FICTIONAL, made-up picture — use only for \"draw/create/make/paint/imagine a picture of...\". It fabricates an image from a description; it has no access to anything real. NEVER use this for a real place, real person, or anything the request implies already exists and has been photographed — use find_photos for those instead. You will never see the result yourself.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string", "description": "A short, clear description of the fictional picture to create, in plain words."]
                    ],
                    "required": ["description"],
                ],
            ],
        ],
        [
            "type": "function",
            "function": [
                "name": "find_photos",
                "description": "Find and show REAL existing photos — use for \"get/find/show me/are there (any) pictures or photos of...\" a real place, person, or thing that has actually been photographed (aerial shots of a town, a landmark, a real animal, etc). This searches real images, unlike generate_image which only fabricates. You will never see the results yourself.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "A short, specific search query for the real photos wanted, including place names."]
                    ],
                    "required": ["query"],
                ],
            ],
        ],
        [
            "type": "function",
            "function": [
                "name": "open_webpage",
                "description": "Show Carl a real webpage, in a browser window right on his own screen — use when he asks to \"bring up\", \"show me\", or \"open\" a specific site or page (e.g. \"show me the weather forecast on the BOM website\", \"open up the Bunnings website\"), rather than just wanting a spoken answer. MUST be called with a url that came back from search_web in THIS same turn — never a url from your own memory or training, even one you're confident about: call search_web first, then pass one of its exact result urls here. A url that didn't come from this turn's search will be refused.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "url": ["type": "string", "description": "One of the exact result urls search_web just returned this turn."]
                    ],
                    "required": ["url"],
                ],
            ],
        ],
    ]

    // MARK: - Groq's rate limits (rebuilt 15/11/2026)
    //
    // Groq's own docs (console.groq.com/docs/rate-limits): the
    // x-ratelimit-*-requests headers always mean requests per DAY, the
    // *-tokens headers always mean tokens per MINUTE, and a 429 carries
    // retry-after (seconds) for whichever limit was actually hit. Carl's
    // account, read live 15/11/2026: 8,000 tokens a minute and 1,000
    // requests a day, with the daily count refilling one request every
    // 86.4s, so its "reset" timer reads tens of minutes after a busy
    // spell. The old code blocked for the LONGER of the two timers (a
    // seconds-long per-minute wall became a 20-minute lockout, "allowance
    // used up") and couldn't read "592ms" at all. Now retry-after decides,
    // short waits are sat out automatically, and the wording says which
    // wall it is.

    /// Waits this long or less are sat out ("One moment, sir") rather than
    /// failing the question.
    private static let quietWaitLimit: Double = 20

    /// Set only by a 429, from retry-after. A 200 clears it.
    private static var blockedUntil: Date?
    /// What the LAST reply said was left of this minute's tokens, and when
    /// it refills — so the next request can wait for room instead of
    /// walking into the wall.
    private static var tokensLeft: Int?
    private static var tokensRefillAt: Date?

    /// Groq's durations: "2" (retry-after), "592ms", "7.66s", "1m26.4s",
    /// "2h59m59.56s".
    private static func parseDuration(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        if let plain = Double(raw) { return plain }
        guard let re = try? NSRegularExpression(pattern: #"([\d.]+)(ms|h|m|s)"#) else { return nil }
        var total = 0.0
        for match in re.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let numberRange = Range(match.range(at: 1), in: raw),
                  let unitRange = Range(match.range(at: 2), in: raw),
                  let number = Double(raw[numberRange]) else { continue }
            switch raw[unitRange] {
            case "h":  total += number * 3600
            case "m":  total += number * 60
            case "ms": total += number / 1000
            default:   total += number
            }
        }
        return total > 0 ? total : nil
    }

    /// A seconds figure spoken the way Carl would actually say it.
    private static func formatWait(_ seconds: Double) -> String {
        if seconds < 90 { return "about \(max(1, Int(seconds.rounded()))) seconds" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 { return "about \(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = Int((seconds / 3600).rounded())
        return "about \(hours) hour\(hours == 1 ? "" : "s")"
    }

    /// Seconds still to wait if the last 429 hasn't cleared yet.
    private static func secondsBlocked() -> Double? {
        guard let until = blockedUntil else { return nil }
        let left = until.timeIntervalSinceNow
        return left > 0.2 ? left : nil
    }

    private static func recordRateLimit(_ http: HTTPURLResponse) {
        let header = { (name: String) in http.value(forHTTPHeaderField: name) }
        if http.statusCode == 429 {
            let wait = parseDuration(header("retry-after"))
                ?? parseDuration(header("x-ratelimit-reset-tokens"))
                ?? 10
            blockedUntil = Date().addingTimeInterval(wait)
            return
        }
        blockedUntil = nil
        tokensLeft = header("x-ratelimit-remaining-tokens").flatMap { Int($0) }
        tokensRefillAt = parseDuration(header("x-ratelimit-reset-tokens"))
            .map { Date().addingTimeInterval($0) }
    }

    /// A real wall, said plainly: a short per-minute one, or a long one.
    private static func limitError(_ wait: Double) -> NSError {
        let message = wait > 120
            ? "I've hit the free cloud AI's limit for now. It's back in \(formatWait(wait))."
            : "Groq's asked me to slow down for a moment. Try again in \(formatWait(wait))."
        return NSError(domain: "GroqBrain", code: 429, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// One call to Groq's OpenAI-compatible chat completions endpoint.
    /// Returns the parsed JSON response body; throws on any transport or
    /// status failure so the caller can give an honest spoken explanation.
    /// `onWait(true)` fires while it's sitting out a short rate-limit wait,
    /// `onWait(false)` once it's done.
    static func chat(messages: [[String: Any]],
                     onWait: (Bool) -> Void = { _ in }) async throws -> [String: Any] {
        guard let key = CloudAIKey.load() else {
            throw NSError(domain: "GroqBrain", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The cloud AI isn't set up yet: there's no key on this iPad."
            ])
        }
        defer { onWait(false) }
        let body: [String: Any] = [
            "model": "openai/gpt-oss-120b",
            "messages": messages,
            "tools": toolsSchema,
            "tool_choice": "auto",
            "max_tokens": 400,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<3 {
            if let wait = secondsBlocked() {
                // Behind a 429 wall: sit it out if it's short, else say so.
                guard wait <= quietWaitLimit, attempt < 2 else { throw limitError(wait) }
                onWait(true)
                try await Task.sleep(for: .seconds(wait))
            } else if let left = tokensLeft, left < 2500, let refill = tokensRefillAt {
                // This minute is nearly spent: wait for room rather than
                // walk into the wall. (Cached tokens don't count, so this
                // only waits when there's genuinely little left.)
                let wait = refill.timeIntervalSinceNow
                if wait > 0, wait <= quietWaitLimit {
                    onWait(true)
                    try await Task.sleep(for: .seconds(wait + 0.25))
                }
            }

            var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if let http { recordRateLimit(http) }
            let status = http?.statusCode ?? 0
            if status == 429 { continue }   // the top of the loop waits it out, or explains
            guard status == 200 else {
                throw NSError(domain: "GroqBrain", code: status, userInfo: [
                    NSLocalizedDescriptionKey: explain(status)
                ])
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "GroqBrain", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "The cloud AI's reply came back in a form I couldn't read."
                ])
            }
            return json
        }
        throw limitError(secondsBlocked() ?? 10)
    }

    private static func explain(_ status: Int) -> String {
        switch status {
        case 401: return "The cloud AI rejected the key. Tell Carl to check his Groq key."
        default: return "The cloud AI had a problem (code \(status)). Try again shortly."
        }
    }
}
