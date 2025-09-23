// Simple CORS proxy for JustWatch/Letterboxd content fetching
const https = require('https');
const http = require('http');

module.exports = (req, res) => {
  // Enable CORS
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

  // Validate allowed domains
  const allowedDomains = ['justwatch.com', 'letterboxd.com', 'boxd.it'];
  let urlObj;
  try {
    urlObj = new URL(url);
  } catch (e) {
    res.status(400).json({ error: 'Invalid URL' });
    return;
  }

  const isAllowed = allowedDomains.some(domain =>
    urlObj.hostname === domain || urlObj.hostname.endsWith('.' + domain)
  );

  if (!isAllowed) {
    res.status(403).json({ error: 'Domain not allowed' });
    return;
  }

  // Fetch the content
  const protocol = urlObj.protocol === 'https:' ? https : http;

  const options = {
    hostname: urlObj.hostname,
    port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
    path: urlObj.pathname + urlObj.search,
    method: 'GET',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    }
  };

  const request = protocol.request(options, (response) => {
    let data = '';

    response.on('data', (chunk) => {
      data += chunk;
    });

    response.on('end', () => {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.status(200).send(data);
    });
  });

  request.on('error', (error) => {
    res.status(500).json({ error: 'Request failed', message: error.message });
  });

  request.setTimeout(15000, () => {
    request.destroy();
    res.status(408).json({ error: 'Request timeout' });
  });

  request.end();
};