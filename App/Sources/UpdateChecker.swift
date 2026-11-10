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
        /// 官方 SHA256SUMS.txt 里这个包的摘要（没有清单时为 nil）
        var assetSHA256: String? = nil
    }

    private let endpoint = URL(string: "https://api.github.com/repos/yzsm385/JLUGate/releases/latest")!
    private var cached: (date: Date, release: Release?)?
    /// 同一份 Release 里有新版包和 macOS 14 适配包，装错了会打不开：
    /// 适配包只认名字里带 Compat 的资产，绝不能用新包兜底。
    private let wantsCompatAsset: Bool

    init(wantsCompatAsset: Bool = false) {
        self.wantsCompatAsset = wantsCompatAsset
    }

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
            let rawAssets = json["assets"] as? [[String: Any]] ?? []
            let assets: [ReleaseAssetPicker.Asset] = rawAssets.compactMap { asset in
                guard let name = asset["name"] as? String,
                      let raw = asset["browser_download_url"] as? String,
                      let url = URL(string: raw) else { return nil }
                return ReleaseAssetPicker.Asset(name: name, url: url)
            }
            let zip = ReleaseAssetPicker.pick(from: assets, wantsCompat: wantsCompatAsset)
            var release = Release(
                tag: tag,
                name: json["name"] as? String ?? tag,
                pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
                assetURL: zip?.url,
                body: json["body"] as? String ?? "")
            // 顺手取官方清单里这个包的摘要：拿不到就不校验（不阻塞更新）
            if let zip, let checksumAsset = assets.first(where: {
                $0.name.caseInsensitiveCompare("SHA256SUMS.txt") == .orderedSame
            }) {
                release.assetSHA256 = await fetchChecksum(from: checksumAsset.url, for: zip.name)
            }
            cached = (Date(), release)
            return release
        } catch {
            cached = (Date(), nil)
            return nil
        }
    }

    /// 取 SHA256SUMS.txt 并挑出指定包名的摘要。取不到就返回 nil（不阻塞更新）。
    private func fetchChecksum(from url: URL, for assetName: String) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("JLU-Gate/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ChecksumManifest.checksum(for: assetName, in: text)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        UpdateVersion.isNewer(candidate, than: current)
    }
}
