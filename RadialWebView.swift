import SwiftUI
import WebKit

/* ============================================================
   Carl's laptop Radial, running inside the app.
   The page is the real face (RadialPage.swift, generated from the
   laptop's own files). This view tells it what Jarvis is really
   doing, the way the laptop's voice line does:
     waiting for Carl → idle  (sonar ripples, scanner, stars)
     thinking         → thinking (amber tick wheel, HUD arcs)
     speaking         → speaking (starburst, pulsing on each word)
     asleep           → idle, dimmed
   ============================================================ */

struct RadialWebView: UIViewRepresentable {
    @ObservedObject var engine: JarvisEngine

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.loadHTMLString(RadialPage.html, baseURL: nil)
        engine.onWord = { [weak web] in
            web?.evaluateJavaScript("AV.word()", completionHandler: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.show(engine.mode)
        context.coordinator.resizeIfNeeded(web)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var web: WKWebView?
        private var loaded = false
        private var current: JarvisMode = .asleep
        private var lastSize: CGSize = .zero

        func show(_ mode: JarvisMode) {
            current = mode
            if loaded { push() }
        }

        // A native frame change (the split layout resizing this view)
        // doesn't fire the page's own `resize` listener the way an actual
        // browser window resize would — so the canvas kept its OLD pixel
        // buffer while CSS stretched it into the new box, turning the
        // circular orb oval/square-looking (14/11/2026, Carl's catch).
        // Nudging the page's real resize() function by hand after layout
        // settles keeps the canvas's own resolution genuinely in step.
        func resizeIfNeeded(_ web: WKWebView) {
            guard loaded else { return }
            let size = web.bounds.size
            guard size.width > 0, size.height > 0 else {
                // Squeezed to nothing (the pictures maximised, say): forget
                // the old size, so growing back always forces a redraw.
                // Before this, returning to the same size as before counted
                // as "no change" and left the orb blank (15/11/2026).
                lastSize = .zero
                return
            }
            guard size != lastSize else { return }
            lastSize = size
            DispatchQueue.main.async { [weak web] in
                web?.evaluateJavaScript(
                    "if (typeof resize === 'function') { resize(); }",
                    completionHandler: nil)
            }
        }

        // The page has to finish loading before it can be told anything.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            push()
        }

        private func push() {
            let state: String
            let dim: Bool
            switch current {
            case .asleep:    state = "idle";     dim = true
            case .listening: state = "idle";     dim = false
            case .thinking:  state = "thinking"; dim = false
            case .speaking:  state = "speaking"; dim = false
            }
            web?.evaluateJavaScript("AV.setState('\(state)'); AV.setDim(\(dim));", completionHandler: nil)
        }
    }
}
