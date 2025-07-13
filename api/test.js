export default async function handler(req, res) {
  console.log('Test API: Request received:', req.method, req.url)
  
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type')

  if (req.method === 'OPTIONS') {
    res.status(200).end()
    return
  }

  res.json({ 
    success: true, 
    message: 'Test API is working',
    timestamp: new Date().toISOString(),
    method: req.method,
    url: req.url
  })
} 