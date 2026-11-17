import Foundation
import FoundationModels

/* ============================================================
   LOCAL BRAIN · Apple's on-device model, Jarvis's "me specialist"
   (15/11/2026, Carl's call). Unlike 14/11/2026's on-device router
   (dropped — see CloudAI.swift/GroqBrain), this is not asked to
   decide between a wide, generalist tool menu, which is what it
   was genuinely bad at. Carl's own split: Local Jarvis handles
   things specific to him (files, email, calendar, his shopping
   list, basic online lookups like weather/news) using a small,
   fixed tool set; Cloud Jarvis (Groq) stays the generalist.
   "Local" describes where the THINKING happens — on this iPad,
   never sent to a cloud server — not whether it has internet: most
   of the time it will, using the network for its own tools (once
   built) and the same cloud voice as Home/Big Brain, same as Cloud
   Jarvis does. Only a genuine loss of network should drop it to
   on-device resources (Apple's own voice) with an honest word to
   Carl that it's temporarily offline — not built yet, flagged for
   the tools pass. Tools come in a later pass — this first build is
   just the on-device conversation itself, so Carl and the brain
   switch both exist before anything is wired to a tool.
   ============================================================ */

enum LocalBrain {
    /// Checked honestly rather than assumed — a call on a device that
    /// can't run it, or with Apple Intelligence switched off, fails
    /// outright with no useful message of its own.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// One running session for as long as the app's open, so the local
    /// brain remembers the conversation the same way Groq's messages array
    /// does for the cloud brain — built once, on the first question asked
    /// of it, from whatever facts/recent-conversations were true then.
    /// Only reset when Carl picks a new vault (JarvisEngine.setVault, same
    /// trigger that clears Groq's own messages), never on every turn: a
    /// session recreated on each call would throw away its own on-device
    /// transcript memory, the whole point of keeping one instance.
    private static var session: LanguageModelSession?

    static func reset() {
        session = nil
    }

    private static func activeSession(instructions: String) -> LanguageModelSession {
        if let session { return session }
        let fresh = LanguageModelSession(instructions: Instructions(instructions))
        session = fresh
        return fresh
    }

    /// Asks the on-device model one question and returns its plain-text
    /// reply, or an honest explanation if it couldn't answer at all.
    static func reply(to question: String, instructions: String) async -> String {
        guard isAvailable else {
            return "The Local Model isn't available on this iPad right now — check Apple Intelligence is turned on in Settings."
        }
        let session = activeSession(instructions: instructions)
        do {
            let response = try await session.respond(to: question)
            return response.content
        } catch {
            return "The Local Model had trouble with that: \(error.localizedDescription)"
        }
    }
}
