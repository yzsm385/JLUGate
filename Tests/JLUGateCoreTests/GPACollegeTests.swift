import Testing
import Foundation
@testable import JLUGateCore

@Suite("GPA：学号 / 账号 → 学院与深链")
struct GPACollegeTests {
    @Test("学号按「学院代码 + 入学年份」识别")
    func studentIDs() {
        let software = GPACollegeDirectory.match("55230123")
        #expect(software?.code == "55")
        #expect(software?.year == 2023)
        #expect(software?.college?.name == "软件学院")

        let computer = GPACollegeDirectory.match("21230123")
        #expect(computer?.code == "21")
        #expect(computer?.year == 2023)
        #expect(computer?.college?.name == "计算机科学与技术学院")

        // 通信的代码是 20；不要把后面的 23 当成学院代码
        let comm = GPACollegeDirectory.match("20230001")
        #expect(comm?.code == "20")
        #expect(comm?.year == 2023)
        #expect(comm?.college?.name == "通信工程学院")
    }

    @Test("邮箱前缀：姓名拼音 + 代码 + 年份")
    func accounts() {
        let computer = GPACollegeDirectory.match("zhangcyy2122")
        #expect(computer?.code == "21")
        #expect(computer?.year == 2022)
        #expect(computer?.college?.name == "计算机科学与技术学院")

        let software = GPACollegeDirectory.match("zhangcyy5522")
        #expect(software?.code == "55")
        #expect(software?.year == 2022)
        #expect(software?.college?.name == "软件学院")

        // 真实登录账号的样子：邮箱前缀本身就带「学院代码 + 入学年份」。
        let email = GPACollegeDirectory.match("zhangcyy5525")
        #expect(email?.code == "55")
        #expect(email?.year == 2025)
        #expect(email?.college?.name == "软件学院")

        // 代码前必须是字母：2122 里的 12 不能被当成学院
        #expect(GPACollegeDirectory.match("zhangcyy2122")?.code == "21")
    }

    @Test("4 位只认年级；认不出就不猜")
    func partialAndUnknown() {
        let yearOnly = GPACollegeDirectory.match("2124")
        #expect(yearOnly?.college == nil)
        #expect(yearOnly?.code == nil)
        #expect(yearOnly?.year == 2024)

        #expect(GPACollegeDirectory.match("zhangshanwu") == nil)
        #expect(GPACollegeDirectory.match("99999999") == nil)
        #expect(GPACollegeDirectory.match("") == nil)
    }

    @Test("去掉邮箱后缀和空格 / 连字符")
    func normalization() {
        #expect(GPACollegeDirectory.match(" 55230123 ")?.code == "55")
        #expect(GPACollegeDirectory.match("55230123@jlu.edu.cn")?.code == "55")
        #expect(GPACollegeDirectory.match("zhang-cyy-5522")?.code == "55")
    }

    @Test("App 的学院名能对上 GPA 学院代码")
    func names() {
        #expect(GPACollegeDirectory.college(forName: "软件学院")?.code == "55")
        #expect(GPACollegeDirectory.college(forName: "计算机科学与技术学院")?.code == "21")
        #expect(GPACollegeDirectory.college(forName: "外国语言文化学院")?.code == "03")
        #expect(GPACollegeDirectory.college(forName: "白求恩口腔医学院")?.code == "33")
        // 基础医学院只应命中 71，不能命中更长的「白求恩医学部（基础医学院）」
        #expect(GPACollegeDirectory.college(forName: "基础医学院")?.code == "71")
        #expect(GPACollegeDirectory.college(forName: "白求恩医学部（基础医学院）")?.code == "78")
        #expect(GPACollegeDirectory.college(forName: "卓越工程师学院") == nil)
    }

    @Test("深链：只放 fragment，学院确定时不再带学号/账号")
    func deepLink() {
        let known = GPALink.make(collegeCode: "55", year: 2023,
                                 studentID: "55230123", account: "zhangcyy5522")
        #expect(known.absoluteString == "https://yzsm385.github.io/JLUGate/#college=55&year=2023")
        #expect(known.query == nil)
        #expect(known.fragment == "college=55&year=2023")

        let unknown = GPALink.make(collegeCode: nil, year: 2024,
                                   studentID: "2124", account: "")
        #expect(unknown.fragment == "year=2024&sid=2124")

        // 登录邮箱前缀优先，不依赖用户再填学号。
        let accountOnly = GPALink.make(collegeCode: nil, year: nil,
                                       studentID: "2124", account: "zhangcyy5525")
        #expect(accountOnly.fragment == "account=zhangcyy5525")

        let none = GPALink.make(collegeCode: nil, year: nil, studentID: nil, account: nil)
        #expect(none.absoluteString == "https://yzsm385.github.io/JLUGate/")
        #expect(none.fragment == nil)
    }
}
