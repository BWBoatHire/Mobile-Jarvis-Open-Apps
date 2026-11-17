import SwiftUI
import UniformTypeIdentifiers
import WebKit

// The app's one screen. (Was ContentView.swift: iCloud lost that file on
// the iPad after it was replaced wholesale, so it lives here now.)

// Which side of the screen is full-width right now. Only meaningful once
// there's something to display (14/11/2026) — with nothing to show,
// Jarvis's own side always takes the whole screen regardless of this.
private enum PaneLayout {
    case split, jarvisFull, displayFull
}

struct JarvisScreen: View {
    @StateObject private var jarvis = JarvisEngine()
    @State private var layout: PaneLayout = .split
    @State private var pickingVault = false
    @State private var editingKey = false
    @State private var keyText = ""
    @State private var editingCloudKey = false
    @State private var cloudKeyText = ""
    @State private var editingVoiceKey = false
    @State private var voiceKeyText = ""
    @State private var voiceIDText = ""
    // The iPad's own chat window (15/11/2026, #46 follow-on): the orb
    // centred at the top with the chat card beneath it (Carl's mock-up).
    // 400pt, not a small corner icon — the face's particle orb needs real
    // room to read; tested down to 110pt and it washed out to a white
    // blob below ~300pt (Carl's own side-by-side comparison, chose 400).
    @State private var chatOpen = false
    private let chatOrbSize: CGFloat = 400
    // The full on-screen keyboard covers about the bottom 40% of the
    // screen in landscape, and the 400pt orb above the chat card left the
    // typing box hidden behind it (15/11/2026, Carl's catch). While it's
    // up, the orb's space folds away (the orb itself keeps its size) so
    // the card gets the whole visible screen;
    // the card header's status dot and line keep showing what Jarvis is
    // doing.
    @State private var keyboardUp = false

    private var vaultButtonTitle: String {
        jarvis.hasVault ? "Change vault folder" : "Choose the Jarvis vault folder"
    }

    private var searchButtonTitle: String {
        jarvis.hasSearchKey ? "Change search key" : "Add web search key"
    }

    private var cloudKeyButtonTitle: String {
        jarvis.hasCloudAIKey ? "Change cloud AI key" : "Add cloud AI key"
    }

    private var voiceKeyButtonTitle: String {
        jarvis.hasCloudVoiceKey ? "Change Jarvis voice key" : "Add Jarvis voice key"
    }

    // Anything that belongs on the display side — pictures, or a real
    // webpage (14/11/2026, #36). Drives whether the split exists at all.
    private var hasDisplayContent: Bool {
        jarvis.generatedImage != nil || !jarvis.foundPhotos.isEmpty || jarvis.openWebPage != nil
    }

    // The Radial itself has to actually shrink to match Jarvis's own
    // pane, not just sit full-screen behind it — otherwise the display
    // pane simply covers the right half of a still-full-width orb instead
    // of it re-centring in the real space left for it (14/11/2026, Carl's
    // catch from the real screenshot).
    private func jarvisWidth(total: CGFloat) -> CGFloat {
        if layout == .displayFull { return 0 }
        if hasDisplayContent && layout == .split { return total / 2 }
        return total
    }

    private func displayWidth(total: CGFloat) -> CGFloat {
        layout == .displayFull ? total : total / 2
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Split: Jarvis (Radial + overlay) on the left, pictures
                // (and later web pages) on the right, each maximisable —
                // only while there's actually something to show
                // (14/11/2026, Carl's ask). The Radial stays mounted even
                // at width 0 (displayFull) rather than being removed from
                // the tree, so it never reloads or flickers switching back.
                HStack(spacing: 0) {
                    // One RadialWebView, always — just resized when the
                    // chat opens, never swapped between branches, so it's
                    // never remounted (which would reload the face and
                    // flicker, same reasoning as the displayFull-width-0
                    // case below).
                    //
                    // Chat open (15/11/2026, Carl's mock-up): the orb sits
                    // centred at the top of this side, trimmed to a circle
                    // (a square box chopped the face's outer rings off at
                    // its edges, Carl's catch), with the chat card docked
                    // beneath it — not a bare corner orb over an invisible
                    // panel, which is what the first pass looked like.
                    ZStack(alignment: .top) {
                        VStack(spacing: 16) {
                            ZStack {
                                RadialWebView(engine: jarvis)
                                // Tap the orb (full-size, or the chat-open
                                // one) to start talking, or to stop.
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { jarvis.orbTapped() }
                            }
                            .frame(width: chatOpen ? chatOrbSize : nil,
                                   height: chatOpen ? chatOrbSize : nil)
                            .clipShape(chatOpen ? AnyShape(Circle()) : AnyShape(Rectangle()))
                            // Keyboard up: fold away the SPACE the orb sits
                            // in, never the orb itself. Shrinking the orb's
                            // own view to zero left it blank afterwards: the
                            // face skips redrawing at zero size, so when it
                            // came back to 400pt nothing told it to redraw
                            // (15/11/2026, Carl's screenshot).
                            .frame(height: chatOpen && keyboardUp ? 0 : nil, alignment: .top)
                            .clipped()
                            .opacity(chatOpen && keyboardUp ? 0 : 1)
                            .padding(.top, chatOpen ? (keyboardUp ? 12 : 36) : 0)

                            if chatOpen {
                                ChatPane(jarvis: jarvis, chatOpen: $chatOpen)
                                    .frame(maxWidth: 720)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                            }
                        }

                        if !chatOpen {
                            jarvisOverlay
                        }
                    }
                    .frame(width: jarvisWidth(total: geo.size.width))
                    .clipped()
                    // .container, not everything: the keyboard must still
                    // push the chat card up, or the typing box sits hidden
                    // behind it.
                    .ignoresSafeArea(.container)

                    if hasDisplayContent, layout != .jarvisFull {
                        displayPane
                            .frame(width: displayWidth(total: geo.size.width))
                            .frame(maxHeight: .infinity)
                            .background(Color.black)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            withAnimation(.easeOut(duration: 0.25)) { keyboardUp = frame.height > 150 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardUp = false }
        }
        // Nothing left to show — drop back to Jarvis full-screen rather
        // than leaving an empty half-pane sitting there.
        .onChange(of: hasDisplayContent) { _, has in
            if !has { layout = .split }
        }
        .sheet(isPresented: $editingKey) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("tvly-...", text: $keyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Your Tavily key. It's kept in this iPad's secure keychain, never in your notes.")
                    }
                }
                .navigationTitle("Web search key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingKey = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            jarvis.setSearchKey(keyText)
                            editingKey = false
                        }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $editingCloudKey) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("gsk_...", text: $cloudKeyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Your Groq key. It's kept in this iPad's secure keychain, never in your notes.")
                    }
                }
                .navigationTitle("Cloud AI key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCloudKey = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            jarvis.setCloudAIKey(cloudKeyText)
                            editingCloudKey = false
                        }
                        .disabled(cloudKeyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $editingVoiceKey) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("ElevenLabs API key", text: $voiceKeyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Voice ID", text: $voiceIDText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("The same voice Home Jarvis uses on the laptop. Both are kept in this iPad's secure keychain, never in your notes.")
                    }
                }
                .navigationTitle("Jarvis voice key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingVoiceKey = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            jarvis.setCloudVoiceKey(voiceKeyText, voiceID: voiceIDText)
                            editingVoiceKey = false
                        }
                        .disabled(voiceKeyText.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  voiceIDText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .fileImporter(isPresented: $pickingVault, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { jarvis.setVault(url) }
        }
    }

    // Jarvis's own side: orb status, subtitles, settings links. Pictures
    // and (later) web pages live in displayPane instead (14/11/2026).
    private var jarvisOverlay: some View {
        VStack(spacing: 14) {
            Spacer()

            Text(jarvis.statusLine)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            // Which model's listening — switched by saying "switch to the
            // local/cloud model", same phrases as Home Jarvis on the
            // laptop (16/11/2026).
            Text(jarvis.brain == .local ? "Mobile Jarvis · Local Model" : "Mobile Jarvis · Cloud Model")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

            // Subtitles: handy when the room's noisy or Carl's in public.
            VStack(spacing: 8) {
                if !jarvis.heard.isEmpty {
                    Text("“\(jarvis.heard)”")
                        .foregroundStyle(.white.opacity(0.55))
                }
                if !jarvis.answer.isEmpty {
                    Text(jarvis.answer)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 620)
            .padding(.horizontal, 24)

            // The chat window, open any time (not gated to asleep the
            // way the settings gear is below) — typing should work
            // mid-conversation too (15/11/2026, #46 follow-on).
            // 44x44 tap target (Apple's own minimum) on an icon that's
            // only ~20pt — without it, a tap just outside the glyph fell
            // through to the full-screen "tap anywhere to talk" layer
            // behind it and started listening instead (15/11/2026, Carl's
            // catch, real screenshot). Same fix applied to the maximise
            // and settings icons below, since they're built the same way
            // and share the identical risk.
            Button {
                chatOpen = true
            } label: {
                Image(systemName: "message.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, 2)

            if hasDisplayContent {
                Button {
                    layout = (layout == .jarvisFull) ? .split : .jarvisFull
                } label: {
                    Image(systemName: layout == .jarvisFull
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.top, 2)
            }

            // Settings: one small icon, only while idle, rather than four
            // permanent lines of text (14/11/2026, Carl's catch — the
            // first pass at this only fixed the pictures, not this).
            if jarvis.mode == .asleep {
                Menu {
                    Button {
                        pickingVault = true
                    } label: {
                        Text(vaultButtonTitle)
                    }
                    Button {
                        keyText = ""
                        editingKey = true
                    } label: {
                        Text(searchButtonTitle)
                    }
                    Button {
                        cloudKeyText = ""
                        editingCloudKey = true
                    } label: {
                        Text(cloudKeyButtonTitle)
                    }
                    Button {
                        voiceKeyText = ""
                        voiceIDText = ""
                        editingVoiceKey = true
                    } label: {
                        Text(voiceKeyButtonTitle)
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 40)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .allowsHitTesting(false)
        }
    }

    // The right-hand side: pictures, or a real webpage (14/11/2026, #36).
    // Its own maximise control plus a close that clears everything on
    // it, rather than one close button per picture (Carl's ask).
    private var displayPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    layout = (layout == .displayFull) ? .split : .displayFull
                } label: {
                    Image(systemName: layout == .displayFull
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                }
                Spacer()
                Button {
                    jarvis.clearDisplay()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .font(.title3)
            .foregroundStyle(.white.opacity(0.7))
            .padding([.horizontal, .top], 16)

            if let url = jarvis.openWebPage {
                WebPageView(url: url)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let picture = jarvis.generatedImage {
                            ShareableImage(image: picture, maxWidth: .infinity, maxHeight: 420)
                        }
                        ForEach(Array(jarvis.foundPhotos.enumerated()), id: \.offset) { _, photo in
                            ShareableImage(image: photo, maxWidth: .infinity, maxHeight: 420)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
        }
    }
}

// The iPad's own chat window (15/11/2026, #46 follow-on) — typed parity
// with the laptop's radial-float/chat.html, docked beneath the orb rather
// than a separate window, since there's only one screen here to share.
// Rebuilt the same day to match Carl's mock-up and the laptop window: a
// real card with a header, voice bar, labelled bubbles and compose row
// (the first pass had no background of its own, so on black it was
// invisible apart from a stray text field at the bottom of the screen).
// No "+" attach button: nothing on the iPad can pick a photo or file for
// Jarvis yet, so it would be a new feature, not part of the chat box.
private struct ChatPane: View {
    @ObservedObject var jarvis: JarvisEngine
    @Binding var chatOpen: Bool
    @State private var text = ""

    // The laptop chat window's own palette, so both read as one Jarvis.
    private static let card = Color(red: 0.043, green: 0.055, blue: 0.078)    // #0b0e14
    private static let bar = Color(red: 0.086, green: 0.106, blue: 0.149)     // #161b26
    private static let line = Color(red: 0.47, green: 0.63, blue: 0.86).opacity(0.16)
    private static let accent = Color(red: 0.30, green: 0.64, blue: 1.0)      // #4da3ff
    private static let muted = Color(red: 0.56, green: 0.60, blue: 0.67)      // #8e98aa
    private static let youFill = LinearGradient(
        colors: [Color(red: 0.24, green: 0.56, blue: 0.94), Color(red: 0.16, green: 0.37, blue: 0.77)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private var dotColour: Color {
        switch jarvis.mode {
        case .asleep:    return Self.accent
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .cyan
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && jarvis.mode != .thinking
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            voiceBar
            feed
            compose
        }
        .background(Self.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Self.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColour)
                .frame(width: 9, height: 9)
                .shadow(color: dotColour, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text("Jarvis")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(jarvis.statusLine)
                    .font(.caption)
                    .foregroundStyle(Self.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(jarvis.brain == .local ? "Local Model" : "Cloud Model")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(red: 0.74, green: 0.85, blue: 1))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Self.accent.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Self.accent.opacity(0.3), lineWidth: 1))
            Button {
                chatOpen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Self.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Self.bar)
        .overlay(alignment: .bottom) { Self.line.frame(height: 1) }
    }

    // Mic does exactly what tapping the orb does — the iPad has no
    // always-open mic to silence the way the laptop does, so there's no
    // Handsfree/Wake Word switch here (agreed in the mock-up).
    private var voiceBar: some View {
        HStack(spacing: 8) {
            Button {
                jarvis.orbTapped()
            } label: {
                barIcon(jarvis.mode == .listening ? "mic.fill" : "mic",
                        lit: jarvis.mode == .listening)
            }
            Button {
                jarvis.toggleMute()
            } label: {
                barIcon(jarvis.voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        lit: jarvis.voiceMuted)
            }
            Slider(value: Binding(get: { Double(jarvis.voiceVolume) },
                                  set: { jarvis.setVolume(Float($0)) }),
                   in: 0...1)
                .tint(Self.accent)
                .frame(maxWidth: 200)
                .disabled(jarvis.voiceMuted)
                .opacity(jarvis.voiceMuted ? 0.4 : 1)
                .padding(.leading, 6)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .bottom) { Self.line.frame(height: 1) }
    }

    // 44x44 tap target round a smaller drawn button, Apple's own minimum
    // (the same lesson as the chat icon's fall-through tap, 15/11/2026).
    private func barIcon(_ name: String, lit: Bool) -> some View {
        Image(systemName: name)
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(lit ? Color(red: 0.18, green: 0.44, blue: 0.84) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Self.line, lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if jarvis.chatLines.isEmpty {
                        Text("Type below, or tap the mic to talk.")
                            .font(.footnote)
                            .foregroundStyle(Self.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(jarvis.chatLines) { line in
                        bubble(line).id(line.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: jarvis.chatLines.count) { _, _ in
                guard let last = jarvis.chatLines.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var compose: some View {
        HStack(spacing: 8) {
            // SwiftUI's own field. A UIKit UITextField was tried here
            // (15/11/2026) to get round Swift Playgrounds not passing a
            // separate keyboard's typing to text boxes — it didn't help, and
            // it ballooned to fill the card. That keyboard fault is in
            // Playgrounds itself (Apple forum threads 715614, 849019,
            // 857070); the on-screen keyboard works.
            TextField("Type or paste a message to Jarvis…", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.line, lineWidth: 1))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Self.youFill, in: RoundedRectangle(cornerRadius: 10))
                    .opacity(canSend ? 1 : 0.4)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Self.line.frame(height: 1) }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        jarvis.submitTyped(t)
        text = ""
    }

    @ViewBuilder
    private func bubble(_ line: ChatLine) -> some View {
        let isYou = line.who == .you
        HStack {
            if isYou { Spacer(minLength: 60) }
            VStack(alignment: isYou ? .trailing : .leading, spacing: 2) {
                Text(isYou ? "You" : "Jarvis")
                    .font(.caption2)
                    .foregroundStyle(isYou ? Color.white.opacity(0.7) : Self.accent)
                Text(line.text)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(isYou ? .trailing : .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isYou {
                    RoundedRectangle(cornerRadius: 12).fill(Self.youFill)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.055))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.line, lineWidth: 1))
                }
            }
            if !isYou { Spacer(minLength: 60) }
        }
    }
}

// A real, live webpage inside Jarvis's own screen — never handed off to
// Safari, the same one-interface principle behind dropping the Gemini
// hand-off this morning (14/11/2026, backlog #36).
private struct WebPageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url { web.load(URLRequest(url: url)) }
    }
}

// A picture with somewhere to actually go — a dark card so it reads as
// placed, not pasted on the orb, and a share button (the system sheet:
// Save Image, Copy, AirDrop, Messages, all of it) since a picture Carl
// can't do anything with isn't useful (14/11/2026, Carl's catch).
private struct ShareableImage: View {
    let image: UIImage
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    // Pinch-to-zoom and drag-to-pan, built by hand — SwiftUI's plain
    // Image doesn't get these for free the way the Photos app does
    // (14/11/2026, Carl's catch).
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        // No GeometryReader here on purpose (15/11/2026, #47): one
        // wrapped this image before with its proxy never read, and with
        // nothing sizing against it, it reported back a collapsed,
        // near-zero size regardless of how much room the pane actually
        // had — that's what was squashing every picture to a thumbnail.
        // A resizable, scaled-to-fit image sizes itself correctly
        // straight against its own frame, same as generatedImage above.
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .background(.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        // Simultaneous with the pane's own ScrollView, so pinch/pan don't
        // fight normal scrolling when the picture isn't zoomed in. The pan
        // gesture only actually claims a touch once already zoomed past 1x
        // (`including:`), not just a no-op guard inside it — with photos
        // now filling the pane for real (15/11/2026, #47), a thumb almost
        // always lands on a photo, and a merely-no-op gesture recogniser
        // was still winning part of every scroll touch against the
        // ScrollView, which is what made scrolling crawl and jam (found
        // 15/11/2026 from Carl's live screenshots). Magnification itself
        // stays active at every scale — it's two-finger, so it was never
        // the thing fighting the one-finger scroll, and it's the only way
        // to get scale above 1 in the first place.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = min(max(lastScale * value, 1), 4)
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale <= 1 { offset = .zero; lastOffset = .zero }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                     height: lastOffset.height + value.translation.height)
                }
                .onEnded { _ in lastOffset = offset },
            including: scale > 1 ? .all : .none
        )
        .onTapGesture(count: 2) {
            withAnimation {
                scale = 1; lastScale = 1
                offset = .zero; lastOffset = .zero
            }
        }
        .overlay(alignment: .topTrailing) {
            ShareLink(
                item: Image(uiImage: image),
                preview: SharePreview("Picture", image: Image(uiImage: image))
            ) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(10)
        }
        .shadow(radius: 8)
    }
}
