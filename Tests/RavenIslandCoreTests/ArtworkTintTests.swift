import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct ArtworkTintTests {
    @Test func darkAverageIsLifted() throws {
        let c = try #require(ArtworkTint.readable(red: 0.2, green: 0.02, blue: 0.02))
        #expect(max(c.red, c.green, c.blue) >= 0.75)
        #expect(c.red > c.green); #expect(c.red > c.blue)
    }

    @Test func blackHasNoTint() {
        #expect(ArtworkTint.readable(red: 0, green: 0, blue: 0) == nil)
    }

    @Test func greyHasNoTint() {
        #expect(ArtworkTint.readable(red: 0.3, green: 0.31, blue: 0.3) == nil)
        #expect(ArtworkTint.readable(red: 0.9, green: 0.9, blue: 0.88) == nil)
    }

    @Test func nearBlackHasNoTint() {
        #expect(ArtworkTint.readable(red: 0.03, green: 0.02, blue: 0.02) == nil)
    }

    @Test func vividUnchanged() throws {
        let c = try #require(ArtworkTint.readable(red: 0.1, green: 0.8, blue: 0.3))
        #expect(abs(c.red - 0.1) < 0.01); #expect(abs(c.green - 0.8) < 0.01); #expect(abs(c.blue - 0.3) < 0.01)
    }
}
