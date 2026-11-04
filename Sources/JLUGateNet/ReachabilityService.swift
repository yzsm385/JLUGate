import Foundation
import JLUGateCore

/// 逐站点、逐层测量：DNS → TCP → TLS → HTTP，失败时指出卡在哪一层。
///
/// 用 `URLSessionTaskMetrics` 拿到每阶段耗时；错误码用于判断卡在哪一层。
public struct ReachabilityService: Sendable {
    public static let targets: [(host: String, domestic: Bool)] = [
        ("google.com", false),
        ("brave.com", false),
        ("duckduckgo.com", false),
        ("bing.com", false),
        ("baidu.com", true),
    ]

    public init() {}

    public func checkAll(timeout: Duration = .seconds(8)) async -> [SiteResult] {
        await withTaskGroup(of: SiteResult.self) { group in
            for target in Self.targets {
                group.addTask { await check(host: target.host, domestic: target.domestic, timeout: timeout) }
            }
            var results: [SiteResult] = []
            for await result in group { results.append(result) }
            // 保持固定顺序，便于阅读
            let order = Self.targets.map(\.host)
            return results.sorted { order.firstIndex(of: $0.host)! < order.firstIndex(of: $1.host)! }
        }
    }

    public func check(host: String, domestic: Bool, timeout: Duration = .seconds(8)) async -> SiteResult {
        guard let url = URL(string: "https://\(host)/") else {
            return SiteResult(host: host, stage: .dns, isDomestic: domestic)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeout.components.seconds)
        configuration.timeoutIntervalForResource = TimeInterval(timeout.components.seconds)
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "JLU Gate/0.1 reachability"]

        let box = MetricsBox()
        let delegate = MetricsDelegate(box: box)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let started = ContinuousClock.now
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Self.milliseconds(from: started)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<400).contains(status) {
                return SiteResult(host: host, stage: .ok, httpStatus: status,
                                  milliseconds: elapsed, isDomestic: domestic)
            }
            return SiteResult(host: host, stage: .http, httpStatus: status,
                              milliseconds: elapsed, isDomestic: domestic)
        } catch {
            let stage = Self.stage(for: error, box: box.load())
            return SiteResult(host: host, stage: stage, httpStatus: nil,
                              milliseconds: Self.milliseconds(from: started), isDomestic: domestic)
        }
    }

    /// 根据错误 + 已完成的阶段判断卡在哪一层。
    static func stage(for error: Error, box: URLSessionTaskMetrics?) -> ProbeStage {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return .dns
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorServerCertificateHasUnknownRoot
                : return .tls
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet, NSURLErrorBadServerResponse:
                return .tcp
            case NSURLErrorTimedOut:
                // 超时：看指标里有没有完成过 TLS；完成过就算应用层慢，否则算连不上
                if let transaction = box?.transactionMetrics.last,
                   transaction.secureConnectionEndDate != nil { return .http }
                if let transaction = box?.transactionMetrics.last,
                   transaction.connectEndDate != nil { return .tls }
                return .tcp
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .tcp
            }
        }
        return .tcp
    }

    private static func milliseconds(from start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

final class MetricsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URLSessionTaskMetrics?
    func store(_ metrics: URLSessionTaskMetrics?) {
        lock.lock(); value = metrics; lock.unlock()
    }
    func load() -> URLSessionTaskMetrics? {
        lock.lock(); defer { lock.unlock() }; return value
    }
}

private final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let box: MetricsBox

    init(box: MetricsBox) { self.box = box }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        box.store(metrics)
    }
}
