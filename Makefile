.PHONY: test core-test self-test build release probe release-probe dump-login app clean

# 本工作区跑在受限沙箱里，需要把 SwiftPM 缓存/临时目录指到仓库内。
# 在普通 Mac 上这些变量是可选的（不会造成副作用）。
SANDBOX_ENV = TMPDIR=$(CURDIR)/.build/tmp CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/modulecache
SWIFT_FLAGS = --disable-sandbox --scratch-path .build --cache-path .build/cache

test:
	$(SANDBOX_ENV) swift test $(SWIFT_FLAGS)

core-test:
	$(SANDBOX_ENV) swift test $(SWIFT_FLAGS) --filter JLUGateCoreTests

# 施工机唯一能做的"联网"动作：对 127.0.0.1 的模拟网关跑完整流程
self-test:
	$(SANDBOX_ENV) swift run $(SWIFT_FLAGS) jlugate-probe --self-test --seconds 8 --keepalive 1

build:
	$(SANDBOX_ENV) swift build $(SWIFT_FLAGS)

# 打包 universal CLI（CHECKLIST §10.3）
release-probe:
	$(SANDBOX_ENV) swift build -c release --arch arm64 --arch x86_64 $(SWIFT_FLAGS)
	lipo -info .build/apple/Products/Release/jlugate-probe

# 离线核对 342 字节登录包
dump-login:
	$(SANDBOX_ENV) swift run $(SWIFT_FLAGS) jlugate-probe --dump-login \
		--account 20230001 --password test-pass-2024 --salt 49cb720f \
		--hostname test-mac.local --mac 02:00:00:00:00:01

# App 工程由 XcodeGen 生成（需要 brew install xcodegen）
app:
	cd App && xcodegen generate && open JLUGate.xcodeproj

clean:
	rm -rf .build
