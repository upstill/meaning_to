/// Strip consumed launch query params (?share=, ?invite=, ?addlink=…) from the
/// browser address bar on web; a no-op on other platforms.
export 'url_bar_stub.dart' if (dart.library.html) 'url_bar_web.dart';
