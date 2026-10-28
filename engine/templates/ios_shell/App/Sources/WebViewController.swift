import UIKit
import WebKit

/// Full-screen WKWebView with the web app: local files over
/// `appbuilder://app/`, JavaScript dialogs, downloads (shared through the
/// system sheet), external links in Safari and swipe-back navigation.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let config: ShellConfig
    private let themeColor: UIColor
    private let backgroundColor: UIColor
    private var webView: WKWebView!
    private var downloads: [ObjectIdentifier: URL] = [:]

    init(config: ShellConfig) {
        self.config = config
        themeColor = UIColor(hex: config.themeColor)
        backgroundColor = UIColor(hex: config.backgroundColor)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var prefersStatusBarHidden: Bool { config.fullscreen }
    override var prefersHomeIndicatorAutoHidden: Bool { config.fullscreen }
    override var preferredStatusBarStyle: UIStatusBarStyle { themeColor.isLight ? .darkContent : .lightContent }

    private var startURL: URL {
        let start = config.startUrl
        if start.hasPrefix("https://") || start.hasPrefix("http://"), let url = URL(string: start) {
            return url
        }
        return LocalSchemeHandler.url(for: start) ?? LocalSchemeHandler.url(for: "index.html")!
    }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = backgroundColor

        let configuration = WKWebViewConfiguration()
        let www = Bundle.main.bundleURL.appendingPathComponent("www", isDirectory: true)
        configuration.setURLSchemeHandler(LocalSchemeHandler(root: www), forURLScheme: LocalSchemeHandler.scheme)
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)

        if config.fullscreen {
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: root.topAnchor),
                webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])
        } else {
            // Status bar area in the theme color, like the Android shell.
            let statusBar = UIView()
            statusBar.backgroundColor = themeColor
            statusBar.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(statusBar)
            NSLayoutConstraint.activate([
                statusBar.topAnchor.constraint(equalTo: root.topAnchor),
                statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                statusBar.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
                webView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
                webView.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.trailingAnchor),
            ])
        }
        self.webView = webView
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: startURL))
    }

    // MARK: - Navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        switch scheme {
        case LocalSchemeHandler.scheme, "about", "blob", "data":
            decisionHandler(.allow)
        case "http", "https":
            let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if config.openLinksExternally && mainFrame && url.host != startURL.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        default:
            // tel:, mailto:, sms:, maps:… are handled by iOS.
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// `window.open()` and `target="_blank"`.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.scheme == LocalSchemeHandler.scheme || (!config.openLinksExternally && url.scheme?.hasPrefix("http") == true) {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    // MARK: - Downloads

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            completionHandler(nil)
            return
        }
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let destination = folder.appendingPathComponent(name)
        downloads[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(share, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        showAlert(message: error.localizedDescription) {}
    }

    // MARK: - JavaScript dialogs

    private var cancelTitle: String {
        (Locale.preferredLanguages.first ?? "").hasPrefix("ru") ? "Отмена" : "Cancel"
    }

    private func showAlert(message: String, completion: @escaping () -> Void) {
        guard presentedViewController == nil else {
            completion()
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        showAlert(message: message, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard presentedViewController == nil else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard presentedViewController == nil else {
            completionHandler(nil)
            return
        }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}
