#if os(tvOS)
import Foundation

/// The multiplatform app builds this target for tvOS so the dependency still links.
/// The extension is not embedded in the tvOS app.
@main
enum PowerwallWidgetTVMain {
    static func main() {}
}
#endif
