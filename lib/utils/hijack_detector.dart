import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HijackDetector with WidgetsBindingObserver {
  static final HijackDetector _instance = HijackDetector._internal();
  factory HijackDetector() => _instance;
  HijackDetector._internal();

  bool _isMonitoring = false;
  bool _expectingLaunch = false;
  String? _currentUrl;
  BuildContext? _context;
  OverlayEntry? _overlayEntry;

  void initialize(BuildContext context) {
    _context = context;
    if (!_isMonitoring) {
      WidgetsBinding.instance.addObserver(this);
      _isMonitoring = true;
    }
  }

  void dispose() {
    if (_isMonitoring) {
      WidgetsBinding.instance.removeObserver(this);
      _isMonitoring = false;
    }
    _removeOverlay();
  }

  Future<void> monitorLaunch(String url) async {
    print('HijackDetector: Starting monitoring for URL: $url');
    _expectingLaunch = true;
    _currentUrl = url;

    // Since the hijacking happens WITHIN the app, we need a different approach
    // Wait and then check if the user needs help getting back
    await Future.delayed(const Duration(milliseconds: 3000));

    // After 3 seconds, always show the overlay for letterboxd URLs
    // This gives users an escape route regardless of detection accuracy
    if (_currentUrl != null && (_currentUrl!.contains('letterboxd.com') || _currentUrl!.contains('boxd.it'))) {
      print('HijackDetector: Showing escape overlay for letterboxd URL');
      _handleHijackDetected();
    }

    _expectingLaunch = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('HijackDetector: App lifecycle changed to: $state (expecting launch: $_expectingLaunch)');

    if (_expectingLaunch) {
      if (state == AppLifecycleState.paused) {
        // App fully paused - this is normal external launch
        print('HijackDetector: App paused - normal external launch');
        _expectingLaunch = false;
        _removeOverlay();
      } else if (state == AppLifecycleState.resumed) {
        // App came back to foreground while expecting launch - possible hijack
        print('HijackDetector: App resumed while expecting launch - hijacking detected!');
        _handleHijackDetected();
      }
    }
  }

  void _handleHijackDetected() {
    _expectingLaunch = false;
    print('HijackDetector: Possible hijacking detected for URL: $_currentUrl');

    if (_context != null && _currentUrl != null) {
      _showBackToAppOverlay();
    }
  }

  void _showBackToAppOverlay() {
    print('HijackDetector: Attempting to show overlay');
    print('HijackDetector: _overlayEntry is null: ${_overlayEntry == null}');
    print('HijackDetector: _context is null: ${_context == null}');

    if (_overlayEntry != null || _context == null) {
      print('HijackDetector: Cannot show overlay - entry exists or no context');
      return;
    }

    print('HijackDetector: Creating overlay entry');
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              // Semi-transparent background to ensure visibility
              Container(
                color: Colors.black26,
              ),
              // Floating help button at bottom center
              Positioned(
                bottom: 50,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Letterboxd has hijacked your app!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _returnToApp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Back to App'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _copyUrlToClipboard,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                              foregroundColor: Colors.white,
                            ),
                            child: const Icon(Icons.copy),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _removeOverlay,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                              foregroundColor: Colors.white,
                            ),
                            child: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      print('HijackDetector: Inserting overlay into widget tree');
      Overlay.of(_context!)?.insert(_overlayEntry!);
      print('HijackDetector: Overlay inserted successfully');
    } catch (e) {
      print('HijackDetector: Error inserting overlay: $e');
      _overlayEntry = null;
      return;
    }

    // Auto-remove after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      print('HijackDetector: Auto-removing overlay after 10 seconds');
      _removeOverlay();
    });
  }

  void _returnToApp() {
    _removeOverlay();
    if (_context != null) {
      // Force return to previous screen
      Navigator.of(_context!).pop();
    }
  }

  void _copyUrlToClipboard() {
    if (_currentUrl != null) {
      Clipboard.setData(ClipboardData(text: _currentUrl!));
      _removeOverlay();

      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('URL copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}