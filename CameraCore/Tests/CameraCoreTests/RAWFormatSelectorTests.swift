import Testing

@testable import CameraCore

/// Grader **T1-5** — RAW format selection.
///
/// Verifies that `RAWFormatSelector.select` picks ProRAW vs Bayer correctly
/// and falls back gracefully when a format type is absent.
@Suite("T1-5 RAWFormatSelector")
struct RAWFormatSelectorTests {

    // MARK: Test fixtures

    let proRAW = RAWFormat(pixelFormat: 0x7261_7770, isProRAW: true, isBayerRAW: false)
    let bayer1 = RAWFormat(pixelFormat: 0x7261_7231, isProRAW: false, isBayerRAW: true)
    let bayer2 = RAWFormat(pixelFormat: 0x7261_7232, isProRAW: false, isBayerRAW: true)
    let unknown = RAWFormat(pixelFormat: 0xAAAA_AAAA, isProRAW: false, isBayerRAW: false)

    // MARK: Empty list

    @Test("empty list returns nil regardless of preference")
    func emptyList_preferProRAW() {
        #expect(RAWFormatSelector.select(from: [], preferProRAW: true) == nil)
    }

    @Test("empty list with prefer=false returns nil")
    func emptyList_preferBayer() {
        #expect(RAWFormatSelector.select(from: [], preferProRAW: false) == nil)
    }

    // MARK: preferProRAW = true, ProRAW present

    @Test("preferProRAW=true + ProRAW present → returns a ProRAW format")
    func preferProRAW_proRAWPresent() {
        let formats = [bayer1, proRAW, bayer2]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result?.isProRAW == true)
    }

    @Test("preferProRAW=true + only ProRAW in list → returns ProRAW")
    func preferProRAW_onlyProRAW() {
        let formats = [proRAW]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result?.isProRAW == true)
    }

    @Test("preferProRAW=true + ProRAW first in list → returns ProRAW")
    func preferProRAW_proRAWFirst() {
        let formats = [proRAW, bayer1]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result?.isProRAW == true)
    }

    @Test("preferProRAW=true + ProRAW last in list → still returns ProRAW")
    func preferProRAW_proRAWLast() {
        let formats = [bayer1, bayer2, proRAW]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result?.isProRAW == true)
    }

    // MARK: preferProRAW = true, ProRAW absent

    @Test("preferProRAW=true + no ProRAW → falls back to Bayer")
    func preferProRAW_noProRAW_fallbackToBayer() {
        let formats = [bayer1, bayer2]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result?.isBayerRAW == true)
    }

    @Test("preferProRAW=true + only unknown formats → returns non-nil (best available)")
    func preferProRAW_onlyUnknown() {
        let formats = [unknown]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result != nil)
    }

    // MARK: preferProRAW = false

    @Test("preferProRAW=false + ProRAW+Bayer both present → never picks ProRAW")
    func noPreferProRAW_neverPicksProRAW() {
        let formats = [proRAW, bayer1, bayer2]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: false)
        #expect(result?.isProRAW != true)
    }

    @Test("preferProRAW=false + Bayer only → returns a Bayer format")
    func noPreferProRAW_bayerOnly() {
        let formats = [bayer1, bayer2]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: false)
        #expect(result?.isBayerRAW == true)
    }

    @Test("preferProRAW=false + only ProRAW available → falls back to ProRAW (best available)")
    func noPreferProRAW_onlyProRAWAvailable() {
        // Per spec: preferProRAW=false means "don't prefer ProRAW",
        // but if no Bayer is available the selector picks best available.
        let formats = [proRAW]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: false)
        #expect(result != nil)
    }

    @Test("preferProRAW=false + multiple Bayer formats → returns one of them")
    func noPreferProRAW_multipleBayer() {
        let formats = [bayer1, bayer2]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: false)
        let isBayer = result?.isBayerRAW ?? false
        #expect(isBayer)
    }

    // MARK: Return value identity

    @Test("returned format is a member of the input list")
    func returnedFormatIsMemberOfList() {
        let formats = [bayer1, proRAW]
        let result = RAWFormatSelector.select(from: formats, preferProRAW: true)
        #expect(result != nil)
        let isInList = result == bayer1 || result == proRAW
        #expect(isInList)
    }

    @Test("single Bayer format list returns that format regardless of preference")
    func singleBayerFormat_alwaysReturned() {
        let formats = [bayer1]
        let result1 = RAWFormatSelector.select(from: formats, preferProRAW: true)
        let result2 = RAWFormatSelector.select(from: formats, preferProRAW: false)
        #expect(result1 == bayer1)
        #expect(result2 == bayer1)
    }
}
