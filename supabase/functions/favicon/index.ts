import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  const { searchParams } = new URL(req.url)
  const domain = searchParams.get('domain')

  if (!domain) {
    return new Response('Missing domain', { status: 400, headers: CORS_HEADERS })
  }

  const token = Deno.env.get('LOGO_DEV_TOKEN') ?? ''
  const logoUrl = `https://img.logo.dev/${domain}?token=${token}&size=64`

  try {
    const response = await fetch(logoUrl)
    if (!response.ok) {
      return new Response('Not found', { status: 404, headers: CORS_HEADERS })
    }
    const imageData = await response.arrayBuffer()
    const contentType = response.headers.get('content-type') ?? 'image/png'
    return new Response(imageData, {
      headers: {
        ...CORS_HEADERS,
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=604800',
      },
    })
  } catch (e) {
    return new Response('Error fetching icon', { status: 500, headers: CORS_HEADERS })
  }
})
