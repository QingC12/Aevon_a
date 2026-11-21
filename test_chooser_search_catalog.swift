import Foundation
@main struct TestChooserSearchCatalog {
    static func ids(_ query: String, in rows: [[String: String]]) -> [String] {
        rows.filter { ChooserSearch.matches(query: query, name: $0["name"] ?? "", identifier: $0["identifier"] ?? "") }
            .compactMap { $0["identifier"] }.sorted()
    }
    static func main() {
        for _ in 0..<200 {
            STHTestPrepareSearchCatalog(false)
            guard let rows = STHChooserSnapshotUnpinned() else { preconditionFailure("Catalog unexpectedly unavailable") }
            assert(rows.count == 3)
            assert(ids(" 微信 ", in: rows) == ["com.tencent.xin"])
            assert(ids("TENCENT.XIN", in: rows) == ["com.tencent.xin"])
            assert(ids("Ｍｉｎｉｓ", in: rows) == ["com.openminis.app"])
            assert(ids("设置", in: rows) == ["com.apple.Preferences"])
            assert(ids("已添加", in: rows).isEmpty && ids("截图", in: rows).isEmpty)
            assert(ids("absent", in: rows).isEmpty)
            assert(ids("", in: rows).count == 3)
            STHTestAssertSearchReleased()
            STHTestPrepareSearchCatalog(true)
            guard let refreshed = STHChooserSnapshotUnpinned() else { preconditionFailure("Refreshed catalog unavailable") }
            assert(ids("微信", in: refreshed).isEmpty && refreshed.count == 2)
            STHTestAssertSearchReleased()
        }
        print("Chooser catalog/search integration: 200 Chinese/name/ID/width-fold/clear cycles, pinned and virtual entries excluded, refreshed pin state honored")
    }
}
