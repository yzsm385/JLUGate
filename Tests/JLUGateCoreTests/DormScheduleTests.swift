import Testing
import Foundation
@testable import JLUGateCore

@Suite("宿舍作息提醒：只按北京时间")
struct DormScheduleTests {
    /// 用 UTC 构造"北京时间某天某时"，避免测试机时区影响
    private func beijing(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = DormSchedule.beijingTimeZone
        return formatter.date(from: iso)!
    }

    @Test("周日晚 23:00：还有 30 分钟断电")
    func sundayEvening() {
        // 2026-11-08 是周日
        #expect(DormSchedule.care(at: beijing("2026-11-08T23:00:00+08:00"))
                == DormSchedule.Care(kind: .blackoutSoon, minutes: 30))
    }

    @Test("断电前 10 分钟内：催睡觉")
    func imminent() {
        #expect(DormSchedule.care(at: beijing("2026-11-08T23:25:00+08:00"))
                == DormSchedule.Care(kind: .blackoutImminent, minutes: 5))
    }

    @Test("23:30 之后：已经熄灯")
    func afterBlackout() {
        #expect(DormSchedule.care(at: beijing("2026-11-08T23:40:00+08:00"))?.kind == .afterBlackout)
        // 周一 00:40 还算是周日晚
        #expect(DormSchedule.care(at: beijing("2026-11-09T00:40:00+08:00"))?.kind == .afterBlackout)
    }

    @Test("周五、周六夜里不断电：只轻劝一句")
    func weekend() {
        #expect(DormSchedule.care(at: beijing("2026-11-13T23:40:00+08:00"))?.kind == .weekendFree)
        // 周六凌晨 00:10（周五夜）也算周末
        #expect(DormSchedule.care(at: beijing("2026-11-14T00:10:00+08:00"))?.kind == .weekendFree)
        // 周日凌晨 00:10（周六夜）同样是周末
        #expect(DormSchedule.care(at: beijing("2026-11-15T00:10:00+08:00"))?.kind == .weekendFree)
    }

    @Test("早八：工作日 07:30–08:30")
    func morning() {
        #expect(DormSchedule.care(at: beijing("2026-11-09T07:45:00+08:00"))?.kind == .morningClass)
        #expect(DormSchedule.care(at: beijing("2026-11-09T07:29:00+08:00")) == nil)
        // 周六没有早八
        #expect(DormSchedule.care(at: beijing("2026-11-14T07:45:00+08:00")) == nil)
    }

    @Test("接上课表之后：没早八就劝你睡懒觉")
    func sleepIn() {
        struct NoClass: TimetableLookup {
            func hasClassAtEight(on day: Date) -> Bool? { false }
        }
        struct HasClass: TimetableLookup {
            func hasClassAtEight(on day: Date) -> Bool? { true }
        }
        struct Unknown: TimetableLookup {
            func hasClassAtEight(on day: Date) -> Bool? { nil }
        }
        let morning = beijing("2026-11-09T07:45:00+08:00")
        #expect(DormSchedule.care(at: morning, timetable: NoClass())?.kind == .sleepIn)
        #expect(DormSchedule.care(at: morning, timetable: HasClass())?.kind == .morningClass)
        #expect(DormSchedule.care(at: morning, timetable: Unknown())?.kind == .morningClass)
        // 还没接课表：保持原来的"工作日默认有早八"
        #expect(DormSchedule.care(at: morning)?.kind == .morningClass)
    }

    @Test("下午不打扰")
    func daytimeQuiet() {
        #expect(DormSchedule.care(at: beijing("2026-11-09T15:00:00+08:00")) == nil)
    }

    @Test("同一时刻不管系统时区怎么设，判断都一样")
    func timezoneIndependent() {
        let instant = beijing("2026-11-08T23:00:00+08:00")
        // 同一瞬间（UTC 15:00）在任何本地时区下都算北京时间 23:00
        #expect(DormSchedule.care(at: instant)?.kind == .blackoutSoon)
        #expect(DormSchedule.beijingTimeZone.secondsFromGMT(for: instant) == 8 * 3600)
    }
}
