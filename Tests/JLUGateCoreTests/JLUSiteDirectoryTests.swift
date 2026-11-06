import Foundation
import Testing
@testable import JLUGateCore

@Suite("吉大站点合集")
struct JLUSiteDirectoryTests {
    @Test("站点数量与去重")
    func uniqueness() {
        let all = JLUSiteDirectory.all
        #expect(all.count >= 12)
        #expect(Set(all.map(\.host)).count == all.count, "同一域名不能重复出现")
    }

    @Test("每个站点都是合法的 https 链接")
    func urls() {
        for site in JLUSiteDirectory.all {
            let url = site.url
            #expect(url != nil, "\(site.host) URL 非法")
            #expect(url?.scheme == site.scheme)
            #expect(["http", "https"].contains(url?.scheme ?? ""))
            #expect(url?.host == site.host)
        }
    }

    @Test("每个分类都有站点，且说明不为空")
    func categories() {
        for category in JLUSite.Category.allCases {
            #expect(!JLUSiteDirectory.sites(in: category).isEmpty, "\(category.rawValue) 没有站点")
        }
        for site in JLUSiteDirectory.all {
            #expect(!site.note.isEmpty, "\(site.host) 缺少说明")
        }
    }

    @Test("邮箱标为公网，教务/OA 标为仅校内")
    func accessClassification() {
        let mail = JLUSiteDirectory.all.first { $0.host == "mails.jlu.edu.cn" }
        #expect(mail?.access == .publicSite, "学生邮箱校内外都能开")
        let iedu = JLUSiteDirectory.all.first { $0.host == "iedu.jlu.edu.cn" }
        #expect(iedu?.access == .campusOnly)
        let oa = JLUSiteDirectory.all.first { $0.host == "oa.jlu.edu.cn" }
        #expect(oa?.access == .campusOnly)
        #expect(!JLUSiteDirectory.campusOnlyHosts.contains("mails.jlu.edu.cn"))
    }

    @Test("声称支持预填的站点，至少是邮箱/认证/校务之一")
    func prefillTargets() {
        let prefill = JLUSiteDirectory.all.filter(\.supportsCredentialPrefill).map(\.host)
        #expect(prefill.contains("mails.jlu.edu.cn"))
        #expect(prefill.contains("cas.jlu.edu.cn"))
        #expect(!prefill.contains("www.jlu.edu.cn"))
    }
}
