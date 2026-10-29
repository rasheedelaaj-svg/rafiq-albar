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
        config.userContentController.add(context.coordinator, name: "loc")
        config.userContentController.add(context.coordinator, name: "files")
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
        switch message.name {
        case "loc": locCommand(message.body as? [String: Any] ?? [:]); return
        case "files": shareFile(message.body as? [String: Any] ?? [:]); return
        default: break
        }
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

    // Links to other sites (OsmAnd, YouTube, Google) open in their own app or Safari, not inside this web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
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

    // MARK: location for the map, the HUD and trip recording
    // The page sends {cmd: start|record|awake|drain}. Fixes go to window.nativeFix while the app is on screen.
    // With the screen off (only while a trip records) the page is asleep, so fixes are buffered, written to disk,
    // and handed over in order through window.nativeFixBatch when the page asks for them again.
    private var recording = false
    private var pending: [[String: Any]] = []
    private var observing = false
    private lazy var pendingURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-fixes.json")
    }()
    private var canRunInBackground: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false
    }

    private func locCommand(_ body: [String: Any]) {
        switch body["cmd"] as? String {
        case "start":
            setMode(body["mode"] as? String)
            observeAppState()
            if pending.isEmpty, let data = try? Data(contentsOf: pendingURL),
               let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { pending = saved }
            location.requestWhenInUseAuthorization()
            location.startUpdatingLocation()
            reportState()
            drain() // fixes saved before the app was last closed
        case "record":
            recording = body["on"] as? Bool ?? false
            if let mode = body["mode"] as? String { setMode(mode) }
            if canRunInBackground {
                location.allowsBackgroundLocationUpdates = recording
                location.showsBackgroundLocationIndicator = recording
            } else if recording {
                webView?.evaluateJavaScript("window.nativeBgOff=true")
            }
        case "awake":
            UIApplication.shared.isIdleTimerDisabled = body["on"] as? Bool ?? false
        case "drain":
            drain()
        default: break
        }
    }

    private func setMode(_ mode: String?) {
        location.pausesLocationUpdatesAutomatically = false
        location.activityType = .otherNavigation
        if mode == "eco" {
            location.desiredAccuracy = kCLLocationAccuracyHundredMeters
            location.distanceFilter = 25
        } else {
            location.desiredAccuracy = kCLLocationAccuracyBest
            location.distanceFilter = kCLDistanceFilterNone
        }
    }

    // Off screen and not recording: stop GPS and compass so the app costs no battery in the background.
    private func observeAppState() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.location.stopUpdatingHeading()
            if !self.recording { self.location.stopUpdatingLocation() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if CLLocationManager.headingAvailable() { self.location.startUpdatingHeading() }
            self.location.startUpdatingLocation()
        }
    }

    private func reportState() {
        let state: String
        switch location.authorizationStatus {
        case .denied, .restricted: state = "denied"
        case .notDetermined: state = "wait"
        default: state = "ok"
        }
        DispatchQueue.global().async {
            let off = !CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript("window.nativeLocState&&window.nativeLocState('\(off ? "off" : state)')")
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { reportState() }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { reportState() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes: [[String: Any]] = locations.filter { $0.horizontalAccuracy >= 0 }.map { l in
            ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude, "acc": l.horizontalAccuracy,
             "alt": l.altitude, "vacc": l.verticalAccuracy, "spd": l.speed, "crs": l.course,
             "t": (l.timestamp.timeIntervalSince1970 * 1000).rounded()]
        }
        guard let last = fixes.last else { return }
        if UIApplication.shared.applicationState == .active && pending.isEmpty {
            send("nativeFix", last)
        } else if recording {
            pending += fixes
            if pending.count % 20 == 0 { savePending() }
        }
    }

    private func drain() {
        guard !pending.isEmpty else { return }
        send("nativeFixBatch", pending)
        pending = []
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private func savePending() {
        if let data = try? JSONSerialization.data(withJSONObject: pending) { try? data.write(to: pendingURL, options: .atomic) }
    }

    private func send(_ fn: String, _ value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.\(fn)&&window.\(fn)(\(json))")
    }

    // MARK: files the page exports (GPX, backup): written to a temp file and handed to the share sheet
    private func shareFile(_ body: [String: Any]) {
        guard let name = body["name"] as? String, let text = body["text"] as? String,
              let root = webView?.window?.rootViewController else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = webView
        var top = root
        while let shown = top.presentedViewController { top = shown }
        top.present(sheet, animated: true)
    }
}
