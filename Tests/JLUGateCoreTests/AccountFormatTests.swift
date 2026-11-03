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
