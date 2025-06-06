import 'package:flutter/material.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:file_selector/file_selector.dart' show openFile, XFile, XTypeGroup;
import 'package:permission_handler/permission_handler.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' show Node;
import 'dart:io';
import 'dart:math' show min;

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _cookieController = TextEditingController();
  bool _isLoading = false;
  bool _isTestingConnection = false;
  String? _error;
  List<ProcessedLink>? _fetchedLinks;
  bool _useBrowserless = false;
  bool _showCookieInput = false;
  String? _currentDomain;
  bool _isParsingFile = false;
  String? _selectedFilePath;

  @override
  void initState() {
    super.initState();
    // Check if Browserless API key is available
    _useBrowserless = LinkProcessor.browserlessApiKey != null && 
                      LinkProcessor.browserlessApiKey!.isNotEmpty;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  void _updateCurrentDomain() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _currentDomain = null;
        _showCookieInput = false;
      });
      return;
    }

    try {
      final uri = Uri.parse(url);
      setState(() {
        _currentDomain = uri.host;
        _showCookieInput = true;
      });
    } catch (e) {
      setState(() {
        _currentDomain = null;
        _showCookieInput = false;
      });
    }
  }

  void _addCookie() {
    final cookieStr = _cookieController.text.trim();
    if (cookieStr.isEmpty || _currentDomain == null) return;

    final cookie = LinkProcessor.parseCookieString(cookieStr);
    if (cookie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid cookie format. Use: name=value; domain=.example.com; path=/; secure; httpOnly'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Ensure domain is set
    cookie['domain'] ??= _currentDomain!;
    
    LinkProcessor.addCookie(_currentDomain!, cookie);
    _cookieController.clear();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added cookie for ${cookie['name']}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearCookies() {
    if (_currentDomain == null) return;
    
    LinkProcessor.clearCookies(_currentDomain!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared cookies for $_currentDomain'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _fetchLinks() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _fetchedLinks = null;
    });

    try {
      final url = _urlController.text.trim();
      if (_useBrowserless) {
        setState(() => _isLoading = true);
        try {
          await LinkProcessor.fetchLinksFromBrowserless(
            url,
            _currentDomain!,  // Pass the current domain
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } else {
        final links = await LinkProcessor.fetchLinks(url);
        
        setState(() {
          _fetchedLinks = links;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _testBrowserlessConnection() async {
    final apiKey = LinkProcessor.browserlessApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add BROWSERLESS_API_KEY to your .env file first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _error = null;
    });

    try {
      // Test with a simple URL that should work
      const testUrl = 'https://example.com';
      const testDomain = 'example.com';
      final links = await LinkProcessor.fetchLinksFromBrowserless(
        testUrl,
        testDomain,  // Add the domain parameter
      );
      
      if (links.isEmpty) {
        throw Exception('No links found on test page');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Browserless connection successful!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      String errorMessage = e.toString();
      if (errorMessage.contains('401')) {
        errorMessage = 'Invalid Browserless API key. Please check your .env file.';
      } else if (errorMessage.contains('500')) {
        errorMessage = 'Browserless service error. Please try again later.';
      } else if (errorMessage.contains('timeout')) {
        errorMessage = 'Connection timed out. Please check your internet connection.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection test failed: $errorMessage'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      setState(() {
        _isTestingConnection = false;
      });
    }
  }

  Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid) return;

    print('Checking Android permissions...');  // Debug log
    
    // For Android 13+ (API 33+)
    if (await Permission.photos.status.isGranted &&
        await Permission.videos.status.isGranted &&
        await Permission.audio.status.isGranted) {
      print('Media permissions already granted');  // Debug log
      return;
    }

    // Request media permissions for Android 13+
    if (await Permission.photos.request().isGranted &&
        await Permission.videos.request().isGranted &&
        await Permission.audio.request().isGranted) {
      print('Media permissions granted');  // Debug log
      return;
    }

    // For Android 12 and below
    if (await Permission.storage.status.isGranted) {
      print('Storage permission already granted');  // Debug log
      return;
    }

    // Request storage permission for Android 12 and below
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) {
      print('Storage permission granted');  // Debug log
      return;
    }

    // If we get here, permissions were denied
    print('All permissions denied');  // Debug log
    throw Exception('Storage permission is required to browse files');
  }

  Future<void> _pickAndParseFile() async {
    try {
      print('Starting file pick...');  // Debug log
      setState(() {
        _isParsingFile = true;
        _error = null;
        _fetchedLinks = null;
        _currentDomain = null;
      });

      // Request permissions first (only on Android)
      if (Platform.isAndroid) {
        try {
          await _requestAndroidPermissions();
        } catch (e) {
          print('Permission error: $e');  // Debug log
          setState(() {
            _error = e.toString();
            _isParsingFile = false;
          });
          return;
        }
      }

      try {
        // Use file_selector to pick a file
        print('Opening file picker...');  // Debug log
        final typeGroup = XTypeGroup(
          label: 'HTML',
          extensions: ['html', 'htm'],
          mimeTypes: ['text/html'],
        );
        
        final file = await openFile(
          acceptedTypeGroups: [typeGroup],
        ).catchError((error) {
          print('Error opening file picker: $error');  // Debug log
          throw Exception('Failed to open file picker: $error');
        });
        
        if (file == null) {
          print('No file selected');  // Debug log
          setState(() {
            _isParsingFile = false;
          });
          return;
        }

        print('File selected: ${file.name}');  // Debug log

        // Read the file content
        String fileContent;
        try {
          print('Reading file from path...');  // Debug log
          fileContent = await file.readAsString();
          print('File content length: ${fileContent.length}');  // Debug log
          print('First 500 chars of file:');  // Debug log
          print(fileContent.substring(0, min(500, fileContent.length)));  // Debug log
        } catch (e) {
          print('Error reading file: $e');  // Debug log
          setState(() {
            _error = 'Error reading file: $e';
            _isParsingFile = false;
          });
          return;
        }

        setState(() {
          _selectedFilePath = file.name;
        });

        // Parse the HTML content
        print('Parsing HTML content...');  // Debug log
        final document = html_parser.parse(fileContent);
        
        // Validate that this is a proper HTML document
        if (document.querySelector('html') == null) {
          throw Exception('Not a valid HTML document');
        }

        // First try to get the page URL from og:url meta tag
        String? pageUrl;
        final ogUrl = document.querySelector('meta[property="og:url"]');
        if (ogUrl != null) {
          pageUrl = ogUrl.attributes['content'];
          print('Found og:url: $pageUrl');  // Debug log
        }

        // If no og:url, try canonical link
        if (pageUrl == null) {
          final canonicalLink = document.querySelector('link[rel="canonical"]');
          if (canonicalLink != null) {
            pageUrl = canonicalLink.attributes['href'];
            print('Found canonical URL: $pageUrl');  // Debug log
          }
        }

        // If still no URL, try to find any absolute URL in the document
        if (pageUrl == null) {
          print('Searching for any absolute URL in document...');  // Debug log
          final potentialLinks = document.querySelectorAll('a[href^="http"]');
          print('Found ${potentialLinks.length} absolute URLs');  // Debug log
          
          for (final link in potentialLinks) {
            final href = link.attributes['href'];
            if (href != null) {
              try {
                final uri = Uri.parse(href);
                // If the URL looks like a main site URL (no path or just /)
                if (uri.path.isEmpty || uri.path == '/') {
                  pageUrl = href;
                  print('Found main site URL: $pageUrl');  // Debug log
                  break;
                }
              } catch (e) {
                print('Error parsing URL from link: $e');
              }
            }
          }
        }

        if (pageUrl == null) {
          print('HTML content preview:');  // Debug log
          print(fileContent.substring(0, min(500, fileContent.length)));  // Debug log
          throw Exception('Could not determine the page URL from the HTML file');
        }

        // Now that we have the page URL, set it and extract the domain
        try {
          final uri = Uri.parse(pageUrl!);
          setState(() {
            _currentDomain = uri.host;
            _urlController.text = pageUrl!;
          });
          print('Using page URL: $pageUrl');  // Debug log
          print('Extracted domain: $_currentDomain');  // Debug log
        } catch (e) {
          throw Exception('Invalid URL format in HTML file: $pageUrl');
        }

        // Find all title-card-basic divs first
        print('Searching for title cards...');  // Debug log
        final titleCards = document.querySelectorAll('div.title-card');
        print('Found ${titleCards.length} title cards');  // Debug log
        
        if (titleCards.isEmpty) {
          print('No title cards found. Available classes:');  // Debug log
          final allDivs = document.querySelectorAll('div');
          final classes = allDivs.map((d) => d.className).toSet();
          print(classes.join('\n'));  // Debug log
        }

        // Get the base URL from the page URL we found
        final baseUri = Uri.parse(pageUrl!);
        final baseUrl = '${baseUri.scheme}://${baseUri.host}';
        print('Using base URL for relative links: $baseUrl');  // Debug log
        
        final links = <String>[];
        
        // Process each title card
        for (final card in titleCards) {
          try {
           print('--------------------------------');
           print('Processing title card: ${card.outerHtml.substring(0, min(100, card.outerHtml.length))}...');  // Debug log
            
            // Get the first <a> tag within this card
            final anchor = card.querySelector('a.title-card-heading-wrapper');
            if (anchor == null) {
              print('No link found in title card');  // Debug log
              continue;
            }

            final href = anchor.attributes['href'];
            if (href == null || href.isEmpty) {
              print('Empty href in title card');  // Debug log
              continue;
            }
            // Get the title
                        final title = card.querySelector('h2.title-card-heading');
            if (title == null) {
              print('No title found in title card');  // Debug log
              continue;
            }

            // Get only direct text nodes, ignoring text in child elements
            final titleText = title.nodes
                .where((node) => node.nodeType == Node.TEXT_NODE)
                .map((node) => node.text?.trim() ?? '')
                .where((text) => text.isNotEmpty)
                .join(' ')
                .trim();

            // Get the badge label if it exists
            final badge = card.querySelector('span.title-poster__badge');
            final badgeLabel = badge?.text?.trim();
            if (badgeLabel != null) {
              print('Found badge label: $badgeLabel');  // Debug log
            } else{
              print('No badge label found');  // Debug log
            }

            if (titleText.isEmpty) {
              print('No direct text found in title heading');  // Debug log
              print('Title HTML: ${title.outerHtml}');  // Debug log
              continue;
            }

            print('Title text: $titleText');  // Debug log
            
            // Convert relative URL to absolute
            final absoluteUrl = href.startsWith('http') 
                ? href  // Already absolute
                : '$baseUrl${href.startsWith('/') ? '' : '/'}$href';  // Make relative URL absolute
            print('Converting link: $href -> $absoluteUrl');  // Debug log
            
            links.add('<a href="$absoluteUrl">$titleText</a>');
          } catch (e, stackTrace) {
            print('Error processing title card: $e');  // Debug log
            print('Stack trace: $stackTrace');  // Debug log
            // Continue with next card instead of crashing
            continue;
          }
        }

        print('Processed ${links.length} links from ${titleCards.length} title cards');  // Debug log

        if (links.isEmpty) {
          setState(() {
            _error = 'No links found in title cards';
          });
        } else {
          // Process the links
          print('Processing links...');  // Debug log
          try {
            final processedLinks = await LinkProcessor.processLinksForDisplay(links);
            if (mounted) {  // Check if widget is still mounted
              setState(() {
                _fetchedLinks = processedLinks;
              });
            }
            print('Processed ${processedLinks.length} links');  // Debug log
          } catch (e, stackTrace) {
            print('Error processing links: $e');  // Debug log
            print('Stack trace: $stackTrace');  // Debug log
            if (mounted) {  // Check if widget is still mounted
              setState(() {
                _error = 'Error processing links: $e';
              });
            }
          }
        }
      } catch (e, stackTrace) {
        print('Error in file processing: $e');  // Debug log
        print('Stack trace: $stackTrace');  // Debug log
        if (mounted) {
          setState(() {
            _error = 'Error processing file: $e';
            _isParsingFile = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Error in _pickAndParseFile: $e');  // Debug log
      print('Stack trace: $stackTrace');  // Debug log
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isParsingFile = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isParsingFile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBrowserlessKey = LinkProcessor.browserlessApiKey != null && 
                             LinkProcessor.browserlessApiKey!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Links'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, size: 28),
            onPressed: _isLoading || _isParsingFile ? null : _pickAndParseFile,
            tooltip: 'Browse HTML Files',
            color: Colors.blue.shade700,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // File browsing section - Moved to top
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_open, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Browse HTML File',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading || _isParsingFile ? null : _pickAndParseFile,
                    icon: const Icon(Icons.folder_open, size: 24),
                    label: const Text('Select HTML File', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                      backgroundColor: Colors.blue.shade100,
                      foregroundColor: Colors.blue.shade900,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Error message section
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Selected file section
            if (_selectedFilePath != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Selected file: ${_selectedFilePath!.split('/').last}',
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _selectedFilePath = null;
                          _fetchedLinks = null;
                        });
                      },
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // URL section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Fetch from URL',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      hintText: 'https://example.com',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a URL';
                      }
                      if (!LinkProcessor.isValidUrl(value.trim())) {
                        return 'Invalid URL format';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _updateCurrentDomain(),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _fetchLinks,
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Fetch Links', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
            if (_showCookieInput && _currentDomain != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cookie, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Cookies for $_currentDomain',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _clearCookies,
                          tooltip: 'Clear Cookies',
                          color: Colors.blue.shade700,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _cookieController,
                      decoration: InputDecoration(
                        labelText: 'Cookie',
                        hintText: 'name=value; domain=.$_currentDomain; path=/; secure; httpOnly',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addCookie,
                          tooltip: 'Add Cookie',
                        ),
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter cookies in the format: name=value; domain=.$_currentDomain; path=/; secure; httpOnly',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: _useBrowserless,
                  onChanged: _isLoading ? (value) {} : (value) {
                    if (value && !hasBrowserlessKey) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Browserless API key not found in .env file. Please add BROWSERLESS_API_KEY to your .env file.'),
                          duration: const Duration(seconds: 8),
                          action: SnackBarAction(
                            label: 'OK',
                            onPressed: () {},  // Empty function
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _useBrowserless = value;
                    });
                  },
                ),
                const Text('Use Browserless'),
              ],
            ),
            if (_useBrowserless) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasBrowserlessKey ? Colors.blue.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasBrowserlessKey ? Colors.blue.shade200 : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasBrowserlessKey ? Icons.info_outline : Icons.warning_amber_rounded,
                            color: hasBrowserlessKey ? Colors.blue.shade700 : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hasBrowserlessKey
                                  ? 'Browserless is enabled and will fetch JavaScript-rendered content.'
                                  : 'Browserless API key not found. Add BROWSERLESS_API_KEY to your .env file.',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasBrowserlessKey ? Colors.blue.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasBrowserlessKey) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isTestingConnection ? null : _testBrowserlessConnection,
                      icon: _isTestingConnection
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      tooltip: 'Test Browserless Connection',
                      color: Colors.blue.shade700,
                    ),
                  ],
                ],
              ),
            ],
            if (_isLoading) ...[
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _useBrowserless
                          ? 'Fetching links with Browserless... This may take a few moments.'
                          : 'Fetching links...',
                    ),
                  ],
                ),
              ),
            ],
            if (_isParsingFile) ...[
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Parsing HTML file...'),
                  ],
                ),
              ),
            ],
            if (_fetchedLinks != null) ...[
              const SizedBox(height: 24),
              Text(
                'Found ${_fetchedLinks!.length} links:',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ..._fetchedLinks!.map((link) => Card(
                child: ListTile(
                  leading: link.favicon != null
                      ? Image.network(
                          link.favicon!,
                          width: 32,
                          height: 32,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.link),
                        )
                      : const Icon(Icons.link),
                  title: Text(link.displayTitle),
                  subtitle: Text(link.url),
                  onTap: () {
                    Navigator.pop(context, _fetchedLinks);
                  },
                ),
              )).toList(),
            ],
          ],
        ),
      ),
    );
  }
} 