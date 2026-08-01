import Testing
import Foundation
@testable import MacDLCore

@Suite struct DownloadErrorTests {
    @Test func cancelledNotRetryable() {
        #expect(DownloadError.cancelled.isRetryable == false)
    }

    @Test func fileDeletedNotRetryable() {
        #expect(DownloadError.fileDeleted.isRetryable == false)
    }

    @Test func rangeNotSatisfiableNotRetryable() {
        #expect(DownloadError.rangeNotSatisfiable.isRetryable == false)
    }

    @Test func networkRetryable() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(DownloadError.network(err).isRetryable == true)
    }

    @Test func rangeNotSatisfiableLocalized() {
        let msg = DownloadError.rangeNotSatisfiable.errorDescription ?? ""
        #expect(msg == "Server does not support this download range" || msg == "服务器不支持该下载范围")
    }

    @Test func networkLocalizedIncludesCause() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out"])
        let msg = DownloadError.network(err).errorDescription ?? ""
        #expect(msg.hasPrefix("Network error:") || msg.hasPrefix("网络错误："))
        #expect(msg.contains("timed out"))
    }
}
