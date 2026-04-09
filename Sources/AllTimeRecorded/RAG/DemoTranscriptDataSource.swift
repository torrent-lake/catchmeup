import Foundation

/// Deterministic "demo mode" replacement for `TranscriptDataSource`.
///
/// Returns 3 clean, hand-written transcript chunks all dated 2026-01-28 so the
/// MBA pitch demo can reliably show cross-source stitching (mail + wechat +
/// transcripts) without depending on whatever Whisper decided to hallucinate
/// during recording. Like `DemoCalendarDataSource`, this source is intentionally
/// dumb: it ignores the question and always returns the same ordered list.
struct DemoTranscriptDataSource: DataSource {
    let id = "transcripts"
    let displayName = "Audio Transcripts (Demo)"
    let requiresConsent = false

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        let chunks = Self.demoTranscripts()
        let limited = Array(chunks.prefix(max(topK, 0)))
        return limited.isEmpty ? chunks : limited
    }

    // MARK: - Static demo data

    private static func dateFor(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 28
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }

    private static func demoTranscripts() -> [SourceChunk] {
        [
            SourceChunk(
                id: "transcripts#demo-jan28-0947",
                sourceID: "transcripts",
                title: "2026-01-28 09:47 — NBA 6170 Lecture",
                body: """
                Today I want to make an additional capstone requirement explicit that was \
                not in the original syllabus email. Your final deliverable must include a \
                confusion matrix framing: specifically, how you think about false positives \
                as hallucinations and false negatives as missed retrieval. This is the core \
                Deployment & Control dimension of the rubric. I will not accept final projects \
                that skip this. I am saying this out loud because I know most of you do not \
                re-read the syllabus, and this single requirement is the most common reason \
                projects lose 10 to 15 points on peer grading. Write it down now. If your \
                team is doing anything with retrieval — mail, chat, files, transcripts — you \
                need a slide with the confusion matrix and actual numbers from your eval set. \
                Hand-waved percentages are an automatic deduction.
                """,
                timestamp: dateFor(hour: 9, minute: 47),
                originURI: "catchmeup://transcript/demo/2026-01-28#09:47",
                score: 0.98
            ),
            SourceChunk(
                id: "transcripts#demo-jan28-1712",
                sourceID: "transcripts",
                title: "2026-01-28 17:12 — Team 10 coffee sync",
                body: """
                — So for our capstone, are we doing the AI personal memory pitch?
                — Yeah, I want to lead with the Rewind-Limitless-Meta story, show why \
                local-first wins.
                — Good. And for the eval slide we should actually show real hit-rate numbers, \
                not hand-waved.
                — I can borrow Jin's Claude Max subscription to burn through the eval queries \
                tonight.
                — Just make sure we include the Jan 24 winter storm email in the cross-source \
                demo — it lines up perfectly with the HADM drop email and the wechat subway \
                complaint. That is the cleanest three-source example we have.
                — Agreed. One slide, three citations, one screenshot.
                """,
                timestamp: dateFor(hour: 17, minute: 12),
                originURI: "catchmeup://transcript/demo/2026-01-28#17:12",
                score: 0.94
            ),
            SourceChunk(
                id: "transcripts#demo-jan28-1845",
                sourceID: "transcripts",
                title: "2026-01-28 18:45 — CCAL pickup chat",
                body: """
                — Is this the BA II Plus? It still has the original box.
                — Yeah, twenty bucks. I also threw in the TI-84 as a bonus because my \
                roommate moved out.
                — Perfect. I needed this before the AEM 4531 midterm next week.
                — Tell your friends I still have a mac charger and an iclicker to sell.
                """,
                timestamp: dateFor(hour: 18, minute: 45),
                originURI: "catchmeup://transcript/demo/2026-01-28#18:45",
                score: 0.88
            ),
        ]
    }
}
