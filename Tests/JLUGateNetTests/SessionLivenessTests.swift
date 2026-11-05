import Testing
@testable import JLUGateNet

@Suite("会话存活判定：只认 204")
struct SessionLivenessTests {
    @Test("真的拿到 204 才算在线")
    func healthy() {
        #expect(SessionLiveness.verdict(.healthy) == .online)
    }

    @Test("被门户拦下 = 会话没了（302 / 200 都算）")
    func captivePortal() {
        #expect(SessionLiveness.verdict(
            .captivePortal(statusCode: 302, location: "https://login.jlu.edu.cn/")) == .offline)
        #expect(SessionLiveness.verdict(
            .captivePortal(statusCode: 200, location: nil)) == .offline)
    }

    @Test("完全不通 = 说不准，交给校内探针兜底，别乱判断线")
    func unreachable() {
        #expect(SessionLiveness.verdict(.unreachable(reason: "all targets blocked")) == .inconclusive)
    }
}
