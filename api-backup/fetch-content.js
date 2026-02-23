/**
 * Vercel API proxy for fetching external content (JustWatch, Letterboxd)
 * This bypasses CORS restrictions by fetching content server-side
 */
module.exports = async function handler(req, res) {
  // Enable CORS for your Flutter web app
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  // Only allow GET requests
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { url } = req.query;

  // Validate URL parameter
  if (!url) {
    res.status(400).json({ error: 'URL parameter is required' });
    return;
  }

  // Validate that we only proxy allowed domains for security
  const allowedDomains = [
    'justwatch.com',
    'letterboxd.com',
    'boxd.it'
  ];

  const urlObj = new URL(url);
  const isAllowedDomain = allowedDomains.some(domain =>
    urlObj.hostname === domain || urlObj.hostname.endsWith('.' + domain)
  );

  if (!isAllowedDomain) {
    res.status(403).json({
      error: 'Domain not allowed',
      allowedDomains: allowedDomains
    });
    return;
  }

  try {
    console.log(`Proxying request to: ${url}`);

    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Ch-Ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
      },
      // Set a reasonable timeout
      signal: AbortSignal.timeout(15000) // 15 second timeout
    });

    if (!response.ok) {
      console.error(`HTTP ${response.status} for ${url}`);
      res.status(response.status).json({
        error: `HTTP ${response.status}`,
        url: url
      });
      return;
    }

    const contentType = response.headers.get('content-type');

    // Only process HTML content
    if (!contentType || !contentType.includes('text/html')) {
      res.status(400).json({
        error: 'Only HTML content is supported',
        contentType: contentType
      });
      return;
    }

    const html = await response.text();

    console.log(`Successfully fetched ${html.length} characters from ${url}`);
    console.log(`Response headers:`, Object.fromEntries(response.headers.entries()));
    console.log(`First 500 chars of response:`, html.substring(0, 500));

    // For JustWatch URLs, save the full HTML to help debug
    if (url.includes('justwatch.com')) {
      console.log(`=== FULL JUSTWATCH RESPONSE START ===`);
      console.log(html);
      console.log(`=== FULL JUSTWATCH RESPONSE END ===`);
    }

    // Return the HTML content
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.status(200).send(html);

  } catch (error) {
    console.error('Proxy error:', error);

    if (error.name === 'TimeoutError') {
      res.status(408).json({ error: 'Request timeout' });
    } else if (error.name === 'TypeError' && error.message.includes('fetch')) {
      res.status(502).json({ error: 'Failed to connect to external service' });
    } else {
      res.status(500).json({
        error: 'Internal server error',
        message: error.message
      });
    }
  }
}