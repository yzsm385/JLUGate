import Foundation
import Testing
@testable import JLUGateCore

@Suite("账号格式（邮箱前缀 = 学号/工号）")
struct AccountFormatTests {
    @Test("粘贴完整邮箱会自动去掉域名并小写")
    func normalizesEmail() {
        #expect(AccountFormat.normalize("  ZhangCYY2122@mails.jlu.edu.cn ") == "zhangcyy2122")
        #expect(AccountFormat.normalize("zhangshanwu@MAILS.JLU.EDU.CN") == "zhangshanwu")
        #expect(AccountFormat.normalize("zhangcyy2122") == "zhangcyy2122")
    }

    @Test("学生账号：4 位数字 = 专业代码 2 位 + 入学年份 2 位")
    func studentAccount() {
        let analysis = AccountFormat.analyze("zhangcyy2122@mails.jlu.edu.cn")
        #expect(analysis.normalized == "zhangcyy2122")
        #expect(analysis.kind == .student(professionalCode: "21", enrollmentYear: "22"))
        #expect(analysis.isLikelyValid)
        #expect(analysis.hint.contains("21"))
        #expect(analysis.hint.contains("22 年入学"))
    }

    @Test("教师账号：纯字母")
    func teacherAccount() {
        let analysis = AccountFormat.analyze("zhangshanwu")
        #expect(analysis.kind == .teacherOrVariant)
        #expect(analysis.hint.contains("教师"))
        #expect(analysis.isLikelyValid)
    }

    @Test("纯数字（手机号/旧学号）不算有效账号")
    func numericIsNotAnAccount() {
        let analysis = AccountFormat.analyze("20230001")
        #expect(analysis.kind == .unrecognized)
        #expect(analysis.hint.contains("学生账号"))
    }

    @Test("数字位数不对 / 含符号 都给出针对性提示")
    func malformed() {
        #expect(AccountFormat.analyze("zhangcyy212").kind == .unrecognized)
        #expect(AccountFormat.analyze("zhang-cyy2122").kind == .unrecognized)
        #expect(AccountFormat.analyze("").kind == .unrecognized)
    }

    @Test("格式说明里同时涵盖学生与教师，并点明密码是邮箱密码")
    func guidanceText() {
        #expect(AccountFormat.guidance.contains("学生"))
        #expect(AccountFormat.guidance.contains("教师"))
        #expect(AccountFormat.guidance.contains("邮箱密码"))
    }
}

@Suite("JLU 接入规则：按 MAC 认设备")
struct JLUAccessPolicyTests {
    @Test("MAC 不符的提示要说清三件事：登记值、当前值、怎么改")
    func mismatchHint() {
        let hint = JLUAccessPolicy.macMismatchHint(expected: "02:00:00:00:00:01",
                                                   actual: "02:00:00:00:00:02",
                                                   interfaceName: "en0")
        #expect(hint.contains("02:00:00:00:00:01"))
        #expect(hint.contains("02:00:00:00:00:02"))
        #expect(hint.contains("en0"))
        #expect(hint.contains("自助平台"))
        #expect(hint.contains("不能互改") || hint.contains("不能"))
    }

    @Test("JLU.PC 的说明要点明用的是 Wi-Fi 网卡 MAC")
    func jluPCHint() {
        #expect(JLUAccessPolicy.jluPCHint.contains("Wi-Fi"))
        #expect(JLUAccessPolicy.jluPCHint.contains("登记"))
    }

    @Test("门户页（login.jlu.edu.cn）是系统弹的，不是我们")
    func captiveNote() {
        #expect(JLUAccessPolicy.captivePageNote.contains("login.jlu.edu.cn"))
        #expect(JLUAccessPolicy.captivePageNote.contains("正常现象"))
    }

    @Test("自助平台地址")
    func url() {
        #expect(JLUAccessPolicy.selfServiceURL.absoluteString == "https://ip.jlu.edu.cn/pay")
    }
}
