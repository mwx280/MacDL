import Testing
import Foundation
@testable import MacDL

@MainActor
@Suite struct UpdateModelTests {
    private func makeRelease(tag: String, withAsset: Bool = true) -> UpdateService.Release {
        let assets: [UpdateService.Asset] = withAsset
            ? [UpdateService.Asset(name: "MacDL-\(tag).dmg", downloadURL: URL(string: "https://e.com/\(tag).dmg"), size: 100)]
            : []
        return UpdateService.Release(tagName: tag, name: nil, publishedAt: nil, body: nil, prerelease: true, assets: assets)
    }

    // MARK: - Version comparison

    @Test func compareVersionsBasic() {
        #expect(UpdateService.compareVersions("v0.1.1", "v0.1.0") > 0)
        #expect(UpdateService.compareVersions("v0.1.0", "v0.1.0") == 0)
        #expect(UpdateService.compareVersions("v0.1.0", "v0.1.1") < 0)
    }

    @Test func compareVersionsMultiDigit() {
        #expect(UpdateService.compareVersions("v0.10", "v0.9") > 0)
        #expect(UpdateService.compareVersions("1.2.3", "1.2.3") == 0)
        #expect(UpdateService.compareVersions("1.0", "0.9.9") > 0)
        #expect(UpdateService.compareVersions("2.0", "10.0") < 0)
    }

    // MARK: - Check

    @Test func checkUpToDateWhenNoRelease() async {
        let model = UpdateModel(latestRelease: { _ in nil })
        await model.checkForUpdates()
        guard case .upToDate = model.status else {
            Issue.record("expected upToDate, got \(model.status)")
            return
        }
    }

    @Test func checkUpToDateWhenSameVersion() async {
        let release = makeRelease(tag: "v" + UpdateService.currentVersion)
        let model = UpdateModel(latestRelease: { _ in release })
        await model.checkForUpdates()
        guard case .upToDate = model.status else {
            Issue.record("expected upToDate, got \(model.status)")
            return
        }
    }

    @Test func checkAvailableWhenNewer() async {
        let release = makeRelease(tag: "v9.9.9")
        let model = UpdateModel(latestRelease: { _ in release })
        await model.checkForUpdates()
        guard case .available(let r) = model.status else {
            Issue.record("expected available, got \(model.status)")
            return
        }
        #expect(r.tagName == "v9.9.9")
    }

    @Test func checkNoAssetShowsUpToDate() async {
        let release = makeRelease(tag: "v9.9.9", withAsset: false)
        let model = UpdateModel(latestRelease: { _ in release })
        await model.checkForUpdates()
        guard case .upToDate = model.status else {
            Issue.record("expected upToDate (no installable package), got \(model.status)")
            return
        }
    }

    @Test func checkFailsOnError() async {
        struct TestError: Error {}
        let model = UpdateModel(latestRelease: { _ in throw TestError() })
        await model.checkForUpdates()
        guard case .failed = model.status else {
            Issue.record("expected failed, got \(model.status)")
            return
        }
    }

    // MARK: - Download / install

    @Test func downloadReachesDownloaded() async {
        let release = makeRelease(tag: "v9.9.9")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("update-test-\(UUID().uuidString).dmg")
        let model = UpdateModel(
            latestRelease: { _ in release },
            downloadAsset: { _, progress in progress(0.5); return dest },
            installer: { _ in }
        )
        await model.download(release)
        guard case .downloaded(_, let url) = model.status else {
            Issue.record("expected downloaded, got \(model.status)")
            return
        }
        #expect(url == dest)
        #expect(model.downloadedDMG == dest)
    }

    @Test func downloadFailsSetsFailed() async {
        struct TestError: Error {}
        let release = makeRelease(tag: "v9.9.9")
        let model = UpdateModel(latestRelease: { _ in release }, downloadAsset: { _, _ in throw TestError() })
        await model.download(release)
        guard case .failed = model.status else {
            Issue.record("expected failed, got \(model.status)")
            return
        }
    }

    @Test func installFailureSetsFailed() async {
        struct TestError: Error {}
        let model = UpdateModel(latestRelease: { _ in nil }, downloadAsset: { _, _ in throw TestError() }, installer: { _ in throw TestError() })
        await model.install(URL(fileURLWithPath: "/tmp/x.dmg"))
        guard case .failed = model.status else {
            Issue.record("expected failed, got \(model.status)")
            return
        }
    }
}
