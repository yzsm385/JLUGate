import Foundation
import JLUGateCore

/// 极简更新检查：只查 GitHub 最新 Release，不自动下载、不静默安装。
///
/// 为什么不用 Sparkle：要证书、要签名、要 appcast，对一个菜单栏小工具过重；
/// 用户要的是"能一眼看到有没有新版本，点了能去下载"。
actor UpdateChecker {
    struct Release: Sendable, Equatable {
        let tag: String        // v0.2.2
        let name: String
        let pageURL: URL?
        let assetURL: URL?
        let body: String
    }

    private let endpoint = URL(string: "https://api.github.com/repos/yzsm385/JLUGate/releases/latest")!
    private var cached: (date: Date, release: Release?)?

    func latest(forceRefresh: Bool = false) async -> Release? {
        if !forceRefresh, let cached, Date().timeIntervalSince(cached.date) < 3600 {
            return cached.release
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("JLU-Gate/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return nil }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            let release = Release(
                tag: tag,
                name: json["name"] as? String ?? tag,
                pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
                assetURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                body: json["body"] as? String ?? "")
            cached = (Date(), release)
            return release
        } catch {
            cached = (Date(), nil)
            return nil
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        UpdateVersion.isNewer(candidate, than: current)
    }
}
