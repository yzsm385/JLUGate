import Foundation

/// 国家/地区 → 国旗 Emoji（Unicode 区域指示符号）。
public enum CountryFlag {
    /// 传入 ISO 国家码（JP / KR / CN）或常见中文名（日本 / 韩国 / 中国）。
    /// 认不出来返回 nil（界面上就不显示，不猜）。
    public static func emoji(for country: String?) -> String? {
        guard let country, !country.isEmpty else { return nil }
        let code = GeoConsensusEngine.normalizeCountry(country)
        guard code.count == 2,
              code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard let flagScalar = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }

    /// "🇯🇵 JP" 这种形式；认不出就只留原文。
    public static func label(_ country: String?) -> String {
        guard let country else { return "-" }
        if let flag = emoji(for: country) { return "\(flag) \(country.uppercased())" }
        return country
    }
}
