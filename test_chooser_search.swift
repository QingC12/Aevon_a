import Foundation

@main struct TestChooserSearch {
    static func main() {
        assert(ChooserSearch.matches(query: "", name: "微信", identifier: "com.example.wechat"))
        assert(ChooserSearch.matches(query: "wechat", name: "WeChat", identifier: "com.example.wechat"))
        assert(ChooserSearch.matches(query: "微信", name: "微信读书", identifier: "com.example.reading"))
        assert(ChooserSearch.matches(query: " EXAMPLE ", name: "Other", identifier: "com.example.app"))
        assert(ChooserSearch.matches(query: "cafe", name: "Café", identifier: "com.example.cafe"))
        assert(ChooserSearch.matches(query: "ＡＰＰ", name: "My App", identifier: "org.example.app"))
        assert(!ChooserSearch.matches(query: "nomatch", name: "WeChat", identifier: "com.example.wechat"))
        print("Chooser search passed: localized names, IDs, case/width/diacritic folding and trimming")
    }
}
