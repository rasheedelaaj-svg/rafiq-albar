import SwiftUI
import WebKit
import UserNotifications
import AVFoundation
import CoreLocation

// The app is the same web app hosted on GitHub Pages, so every push to main updates it.
// App-bound domain lets the page keep its offline cache (service worker) inside the app.
let appURL = URL(string: "https://rasheedelaaj-svg.github.io/rafiq-albar/")!

@main
struct RafiqAlbarApp: App {
    init() {
        // keeps Quran and audio playing with the screen locked
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup { WebView().ignoresSafeArea() }
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> AdhanScheduler { AdhanScheduler() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.limitsNavigationsToAppBoundDomains = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "adhan")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.startHeading(for: webView)
        webView.load(URLRequest(url: appURL, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// The page posts [{t: epoch ms, n: prayer name}]; each becomes a system notification,
// so the adhan alert fires even when the app is closed.
final class AdhanScheduler: NSObject, WKScriptMessageHandler, WKUIDelegate, CLLocationManagerDelegate {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let list = message.body as? [[String: Any]] else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        // drop a 30s-or-shorter adhan.caf into the target to replace the default tone
        let sound: UNNotificationSound = Bundle.main.url(forResource: "adhan", withExtension: "caf") != nil
            ? UNNotificationSound(named: UNNotificationSoundName("adhan.caf")) : .default
        for item in list.prefix(60) { // iOS keeps at most 64 pending notifications
            guard let ms = item["t"] as? Double, let name = item["n"] as? String else { continue }
            let date = Date(timeIntervalSince1970: ms / 1000)
            guard date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "حان وقت صلاة \(name)"
            content.sound = sound
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "adhan-\(Int(ms))", content: content, trigger: trigger))
        }
    }

    // Without this WebKit silently denies the page's motion permission inside the app.
    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // True-north heading straight from iOS, pushed to the page's window.nativeHeading.
    private let location = CLLocationManager()
    private weak var webView: WKWebView?

    func startHeading(for webView: WKWebView) {
        self.webView = webView
        location.delegate = self
        location.headingFilter = 1
        location.requestWhenInUseAuthorization()
        if CLLocationManager.headingAvailable() { location.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let h = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        webView?.evaluateJavaScript("window.nativeHeading&&window.nativeHeading(\(h))")
    }
}
