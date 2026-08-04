import Testing
import Foundation
import MacDLCore
@testable import MacDL

@Suite struct NewDownloadModelTests {
    @Test func parsesValidAndInvalidLines() {
        let m = NewDownloadModel()
        m.text = "https://e.com/a.zip\nnot a link\nftp://x.com/b"
        #expect(m.validCount == 1)
        #expect(m.invalidCount == 2)
        #expect(m.hasInvalidLinks)
        #expect(m.queueLines.count == 3)
    }

    @Test func emptyTextHasNoTasks() {
        let m = NewDownloadModel()
        m.text = ""
        #expect(m.validTasks.isEmpty)
        #expect(!m.hasInvalidLinks)
    }

    @Test func extractsTaskNameAndHost() {
        let m = NewDownloadModel()
        m.text = "https://cdn.example.com/dir/video_tutorial.mp4"
        #expect(m.validTasks.count == 1)
        #expect(m.validTasks[0].name == "video_tutorial.mp4")
        #expect(m.validTasks[0].host == "cdn.example.com")
    }

    @Test func detectsDuplicatedNames() {
        let m = NewDownloadModel()
        m.text = "https://e.com/a.zip\nhttps://f.com/a.zip"
        #expect(m.duplicatedNames == ["a.zip"])
    }

    @Test func removeTaskStripsUrlAndSettings() {
        let m = NewDownloadModel()
        m.text = "https://e.com/a.zip\nhttps://f.com/b.zip"
        m.connectionsByURL["https://e.com/a.zip"] = 2
        m.limits["https://e.com/a.zip"] = 102400
        m.removeTask("https://e.com/a.zip")
        #expect(m.queueLines == ["https://f.com/b.zip"])
        #expect(m.connectionsByURL["https://e.com/a.zip"] == nil)
        #expect(m.limits["https://e.com/a.zip"] == nil)
    }

    @Test func appendURLsMergesLines() {
        let m = NewDownloadModel()
        m.text = "https://e.com/a.zip"
        m.appendURLs(["https://f.com/b.zip", " \n https://g.com/c.zip "])
        #expect(m.queueLines == ["https://e.com/a.zip", "https://f.com/b.zip", "https://g.com/c.zip"])
    }

    @Test func probingUpdatesResumeStatus() {
        let m = NewDownloadModel(probe: { url, completion in
            completion(url.absoluteString.contains("resumable") ? true : false)
        })
        m.text = "https://e.com/resumable.zip\nhttps://f.com/not.zip"
        m.detectResumeSupport()
        #expect(m.resumeStatus["https://e.com/resumable.zip"] == true)
        #expect(m.resumeStatus["https://f.com/not.zip"] == false)
        // Probing twice must not re-probe already-checked URLs.
        let probed = m.probedURLs.count
        m.detectResumeSupport()
        #expect(m.probedURLs.count == probed)
    }

    @Test func connectionsAndSpeedFallBackToDefaults() {
        let m = NewDownloadModel(defaultConnections: 4, defaultSpeedLimit: 102400)
        let url = "https://e.com/a.zip"
        #expect(m.connections(for: url) == 4)
        #expect(m.speedLimit(for: url) == 102400)
        m.connectionsByURL[url] = 8
        m.limits[url] = 0
        #expect(m.connections(for: url) == 8)
        #expect(m.speedLimit(for: url) == 0)
    }
}
