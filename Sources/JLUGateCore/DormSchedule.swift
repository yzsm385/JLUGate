import Foundation

/// 宿舍作息提醒：**只按北京时间（UTC+8）算**，不看系统时区——
/// 免得有人把系统时区设成美国，提醒就全乱了。
///
/// 规则（吉林大学宿舍）：
/// - 周日到周四：23:30 断电；
/// - 周五、周六：不断电（下一段是 0 点，不用催）。
public enum DormSchedule {
    /// 北京时间的固定时区（中国没有夏令时，UTC+8 常年不变）
    public static let beijingTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    public enum Kind: Sendable, Equatable {
        /// 距断电 11–60 分钟：温和提醒
        case blackoutSoon
        /// 距断电 0–10 分钟：赶快睡
        case blackoutImminent
        /// 周五/周六夜里：不断电，但还是劝一句
        case weekendFree
        /// 已经熄灯（23:30 之后到 01:30）
        case afterBlackout
        /// 早八：周一至周五 07:30–08:30
        case morningClass
    }

    public struct Care: Sendable, Equatable {
        public let kind: Kind
        /// 距断电还有多少分钟（只有 blackoutSoon / blackoutImminent 有意义）
        public let minutes: Int
        public init(kind: Kind, minutes: Int = 0) {
            self.kind = kind
            self.minutes = minutes
        }
    }

    /// 晚间的"断电日"：周日(1)–周四(4)
    private static func isBlackoutNight(_ weekday: Int) -> Bool { (1...5).contains(weekday) }

    /// 给定时刻该显示哪条提醒；没有就返回 nil。
    public static func care(at date: Date) -> Care? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijingTimeZone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
            return nil
        }
        let minutes = hour * 60 + minute

        // 早八：周一至周五 07:30–08:30
        if (2...6).contains(weekday), minutes >= 7 * 60 + 30, minutes < 8 * 60 + 30 {
            return Care(kind: .morningClass)
        }

        // 00:00–01:30 属于"前一天晚上"
        let early = minutes < 90
        let nightDay = early ? (weekday == 1 ? 7 : weekday - 1) : weekday
        let weekendNight = nightDay == 6 || nightDay == 7   // 周五、周六

        if weekendNight {
            if (!early && minutes >= 23 * 60) || (early && minutes < 30) {
                return Care(kind: .weekendFree)
            }
            return nil
        }

        // 断电夜（周日–周四）
        let blackout = 23 * 60 + 30
        if !early, minutes >= blackout - 60, minutes < blackout {
            let left = blackout - minutes
            return Care(kind: left <= 10 ? .blackoutImminent : .blackoutSoon, minutes: left)
        }
        if (!early && minutes >= blackout) || (early && minutes < 90) {
            return Care(kind: .afterBlackout)
        }
        return nil
    }
}
