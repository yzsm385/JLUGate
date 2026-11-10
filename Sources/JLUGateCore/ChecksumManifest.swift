import Foundation

/// `SHA256SUMS.txt` 的解析（`shasum -a 256` / `sha256sum` 的输出格式）。
///
/// 单独放在 Core 里是为了能测：这份清单决定了"下载的包能不能装"，
/// 解析错了会让正常更新被误判成"被篡改"，比不校验还糟。
public enum ChecksumManifest {
    /// 从清单文本里挑出指定文件名对应的 SHA-256。
    ///
    /// 格式：`<64 位十六进制>  <文件名>`，行首可能有两个空格或一个 `*`
    /// （二进制模式标记）。文件名里可以有空格，所以按"第一段是哈希"切。
    public static func checksum(for name: String, in text: String) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            // 先切出哈希，剩下的都是文件名（可能带 * 前缀）
            guard let split = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let digest = String(line[line.startIndex..<split])
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { continue }
            var file = String(line[split...]).trimmingCharacters(in: .whitespaces)
            if file.hasPrefix("*") { file.removeFirst() }
            if file == wanted { return digest.lowercased() }
        }
        return nil
    }
}
