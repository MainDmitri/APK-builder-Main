import UniformTypeIdentifiers
import WebKit

/// Serves the bundled web app at `appbuilder://app/…` with real MIME types,
/// so ES modules, fetch() of local files, localStorage and IndexedDB work as
/// on a web server. Unknown paths without an extension fall back to
/// index.html (single page apps with client-side routing).
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "appbuilder"
    static let host = "app"

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    static func url(for path: String) -> URL? {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(scheme)://\(host)/\(clean)")
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        guard let file = resolve(url.path) else {
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain; charset=utf-8", data: Data("Not found".utf8))
            return
        }
        do {
            let data = try Data(contentsOf: file)
            respond(urlSchemeTask, url: url, status: 200, mime: Self.mimeType(for: file.pathExtension), data: data)
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resolve(_ rawPath: String) -> URL? {
        var path = rawPath.removingPercentEncoding ?? rawPath
        while path.hasPrefix("/") { path.removeFirst() }
        var file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path == root.path || file.path.hasPrefix(root.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), isDirectory.boolValue {
            file.appendPathComponent("index.html")
        }
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if file.pathExtension.isEmpty {
            let index = root.appendingPathComponent("index.html")
            return FileManager.default.fileExists(atPath: index.path) ? index : nil
        }
        return nil
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": "*",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs", "cjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "webmanifest": return "application/manifest+json"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        case "txt": return "text/plain; charset=utf-8"
        default:
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
