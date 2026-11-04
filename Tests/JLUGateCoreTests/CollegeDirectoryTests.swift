import Foundation
import Testing
@testable import JLUGateCore

@Suite("学院目录与学号识别")
struct CollegeDirectoryTests {
    @Test("目录：数量、去重、https 合法")
    func directory() {
        #expect(CollegeDirectory.all.count >= 40)
        #expect(Set(CollegeDirectory.all.map(\.host)).count == CollegeDirectory.all.count)
        for college in CollegeDirectory.all {
            #expect(college.url?.scheme == "https")
            #expect(college.url?.host == college.host)
            #expect(!college.name.isEmpty)
        }
    }

    @Test("搜索：按中文名与域名都能找到")
    func search() {
        #expect(CollegeDirectory.search("计算机").first?.host == "ccst.jlu.edu.cn")
        #expect(CollegeDirectory.search("ccst").first?.name == "计算机科学与技术学院")
        #expect(CollegeDirectory.search("不存在").isEmpty)
    }

    @Test("学号识别：没学过时返回 nil，学过之后能命中")
    func resolve() {
        var learned: [String: String] = [:]
        let id = "2023 0123 45"
        #expect(CollegeResolver.resolve(studentID: id, learned: learned) == nil)
        let college = CollegeDirectory.college(forHost: "ccst.jlu.edu.cn")!
        CollegeResolver.learn(studentID: id, college: college, into: &learned)
        #expect(CollegeResolver.resolve(studentID: id, learned: learned) == college)
        // 只差后两位的同学也能命中（同一学院前缀）
        #expect(CollegeResolver.resolve(studentID: "2023019999", learned: learned) == college)
    }

    @Test("4 位前缀只作兜底，不覆盖已被占用的学院")
    func fourDigitFallback() {
        var learned: [String: String] = [:]
        let a = CollegeDirectory.college(forHost: "math.jlu.edu.cn")!
        let b = CollegeDirectory.college(forHost: "phy.jlu.edu.cn")!
        CollegeResolver.learn(studentID: "2023011111", college: a, into: &learned)
        CollegeResolver.learn(studentID: "2023022222", college: b, into: &learned)
        // 6 位各自命中
        #expect(CollegeResolver.resolve(studentID: "2023011111", learned: learned) == a)
        #expect(CollegeResolver.resolve(studentID: "2023022222", learned: learned) == b)
        // 4 位兜底仍指向第一次学的学院（不被覆盖）
        #expect(learned["2023"] == a.host)
    }

    @Test("学号形态判断")
    func looksLike() {
        #expect(CollegeResolver.looksLikeStudentID("2023012345"))
        #expect(CollegeResolver.looksLikeStudentID("2023-0123-45"))
        #expect(!CollegeResolver.looksLikeStudentID("zhangcyy2122"))
    }
}
