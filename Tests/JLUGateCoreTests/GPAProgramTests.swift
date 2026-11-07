import Testing
import Foundation
@testable import JLUGateCore

@Suite("GPA：专业与计算器路由")
struct GPAProgramTests {
    @Test("软件学院有 3 个专业，2025 软件工程能直接进计算器")
    func software2025() {
        let majors = GPAProgramDirectory.majors(collegeCode: "55")
        #expect(majors.count == 3)
        #expect(majors.contains { $0.name == "软件工程" })

        let plan = GPAProgramDirectory.plan(collegeCode: "55", major: "软件工程", year: 2025)
        #expect(plan?.year == 2025)
        #expect(plan?.route.hasPrefix("plan.html?plan=") == true)

        let url = plan.flatMap(GPAProgramDirectory.url(for:))
        #expect(url?.absoluteString.hasPrefix("https://yzsm385.github.io/JLUGate/plan.html?plan=") == true)
    }

    @Test("2026 软件工程走专门版计算器")
    func software2026() {
        let plan = GPAProgramDirectory.plan(collegeCode: "55", major: "软件工程", year: 2026)
        #expect(plan?.route == "software.html?cohort=2026")
        let url = plan.flatMap(GPAProgramDirectory.url(for:))
        #expect(url?.absoluteString == "https://yzsm385.github.io/JLUGate/software.html?cohort=2026")
    }

    @Test("没有更早方案时不拿更晚的顶替")
    func noFutureFallback() {
        #expect(GPAProgramDirectory.plan(collegeCode: "55", major: "软件工程", year: 2021) == nil)
        #expect(GPAProgramDirectory.majors(collegeCode: "55", year: 2021).isEmpty)
    }

    @Test("全库路由都能拼成绝对 URL，且不内置 http 域名")
    func allRoutes() {
        #expect(GPAProgramDirectory.planCount > 1000)
        #expect(GPAProgramDirectory.majorsByCollege.count == 48)
        #expect(Set(GPAProgramDirectory.majorsByCollege.keys)
                == Set(GPACollegeDirectory.all.map(\.code)))
        var seen = Set<String>()
        for (_, majors) in GPAProgramDirectory.majorsByCollege {
            for major in majors {
                #expect(!major.plans.isEmpty)
                for plan in major.plans {
                    #expect(!plan.route.isEmpty)
                    #expect(!plan.route.hasPrefix("http"))
                    #expect(seen.insert(plan.route).inserted, "路由重复：\(plan.route)")
                    #expect(GPAProgramDirectory.url(for: plan) != nil)
                }
            }
        }
        #expect(seen.count == GPAProgramDirectory.planCount)
    }
}
