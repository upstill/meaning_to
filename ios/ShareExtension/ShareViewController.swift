import share_handler_ios_models

// The whole implementation lives in the share_handler base class: it reads the
// shared URL/text, writes it into the App Group's UserDefaults, and reopens the
// host app via the ShareMedia-<bundleid> URL scheme. We only need the subclass.
@available(iOS 14.0, *)
class ShareViewController: ShareHandlerIosViewController {
}
