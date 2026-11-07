import Foundation
import CoreFoundation

/// 门户页面的文本解码。
///
/// 吉大门户是 Dr.COM 的老底子：`Content-Type: text/html; charset=gbk`，但 HTML 里又写着
/// `gb2312`，而且接口返回的 `application/javascript` 同样是 GBK。用 UTF-8 硬解会把
/// 中文错误提示变成一串乱码，用户看到的就只剩"登录失败"四个字——所以统一在这里按
/// 服务器声明的编码解；声明缺失或解不开时再退到 GB18030 / UTF-8。
enum PortalTextCoding {
    static func decode(_ data: Data, contentType: String?) -> String {
        decode(data, encoding: charset(in: contentType))
    }

    static func decode(_ data: Data, encoding: String?) -> String {
        switch encoding?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "gbk", "gb2312", "gb_2312-80", "gb18030", "gb_18030-2000":
            return decode(data, ianaName: "GB18030")
                ?? String(decoding: data, as: UTF8.self)
        case "iso-8859-1", "latin1", "windows-1252":
            return String(data: data, encoding: .windowsCP1252)
                ?? String(decoding: data, as: UTF8.self)
        default:
            return String(data: data, encoding: .utf8)
                ?? decode(data, ianaName: "GB18030")
                ?? String(decoding: data, as: UTF8.self)
        }
    }

    static func decode(_ data: Data, ianaName: String) -> String? {
        let charset = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard charset != kCFStringEncodingInvalidId else { return nil }
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(charset))
        return String(data: data, encoding: encoding)
    }

    static func charset(in contentType: String?) -> String? {
        guard let contentType,
              let range = contentType.range(of: #"charset\s*=\s*"?([^;" ]+)"?"#,
                                            options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let match = String(contentType[range])
        return match.split(separator: "=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}
