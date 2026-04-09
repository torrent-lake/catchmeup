import Foundation

/// Data source backed by LEANN's WeChat index. The user already has this
/// index built on their machine (43 MB as of plan time).
struct WeChatDataSource: DataSource {
    let id = "wechat"
    let displayName = "WeChat"
    let requiresConsent = true

    let bridge: any LEANNBridging
    let indexName: String

    init(bridge: any LEANNBridging, indexName: String = "wechat_history_magic_test_11Debug_new") {
        self.bridge = bridge
        self.indexName = indexName
    }

    func query(question: String, topK: Int) async throws -> [SourceChunk] {
        try await bridge.search(index: indexName, query: question, topK: topK)
    }
}
