// tidal-resolve — server-side Tidal link resolution.
//
// The browser can't call the Tidal API directly (CORS), and the client secret
// must not ship in the web bundle. This function does the OAuth
// client-credentials flow + album/track/playlist lookup server-side and returns
// { artist, work }. The Flutter web client calls it via
// supabase.functions.invoke('tidal-resolve', body: { url }); native uses the
// direct TidalApiService instead.
//
// Secrets (set with `supabase secrets set`): TIDAL_CLIENT_ID, TIDAL_CLIENT_SECRET.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const COUNTRY = 'US'

/** Extract { type, id } from a Tidal URL path (…/album/123, /track/123, /playlist/uuid). */
function extractResource(url: string): { type: string; id: string } | null {
  try {
    const segs = new URL(url).pathname.split('/').filter((s) => s.length > 0)
    for (let i = 0; i < segs.length - 1; i++) {
      if (segs[i] === 'album' || segs[i] === 'track' || segs[i] === 'playlist') {
        return { type: segs[i], id: segs[i + 1] }
      }
    }
  } catch (_) {
    // fall through
  }
  return null
}

let cachedToken: { value: string; expiry: number } | null = null

async function getAccessToken(): Promise<string | null> {
  const now = Date.now()
  if (cachedToken && now < cachedToken.expiry) return cachedToken.value

  const clientId = Deno.env.get('TIDAL_CLIENT_ID')
  const clientSecret = Deno.env.get('TIDAL_CLIENT_SECRET')
  if (!clientId || !clientSecret) {
    console.error('tidal-resolve: missing TIDAL_CLIENT_ID / TIDAL_CLIENT_SECRET')
    return null
  }

  const basic = btoa(`${clientId}:${clientSecret}`)
  const resp = await fetch('https://auth.tidal.com/v1/oauth2/token', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  })
  if (!resp.ok) {
    console.error(`tidal-resolve: token request failed ${resp.status}`)
    return null
  }
  const data = await resp.json()
  const token = data.access_token as string
  const expiresIn = (data.expires_in as number) ?? 3600
  cachedToken = { value: token, expiry: now + (expiresIn - 60) * 1000 }
  return token
}

async function fetchResource(type: string, id: string, token: string): Promise<any | null> {
  const plural = type === 'album' ? 'albums' : type === 'track' ? 'tracks' : 'playlists'
  const url = `https://openapi.tidal.com/v2/${plural}/${id}?countryCode=${COUNTRY}`
  const resp = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'accept': 'application/vnd.tidal.v1+json',
    },
  })
  if (!resp.ok) {
    console.error(`tidal-resolve: ${plural}/${id} failed ${resp.status}`)
    return null
  }
  const data = await resp.json()
  return data?.resource ?? null
}

/** Map a Tidal resource to { artist, work }. */
function toArtistWork(type: string, resource: any): { artist: string; work: string } | null {
  const artists = resource?.artists
  const artistName = Array.isArray(artists) && artists.length > 0 ? artists[0]?.name : null
  const title = resource?.title as string | undefined

  if (type === 'playlist') {
    // Playlists have no single artist; use the playlist name as the work.
    if (title) return { artist: resource?.owner ?? title, work: title }
    return null
  }
  if (artistName && title) return { artist: artistName, work: title }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })

  try {
    // Accept the URL from a JSON body (supabase.functions.invoke) or ?url= query.
    let url: string | null = null
    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}))
      url = body?.url ?? null
    }
    if (!url) url = new URL(req.url).searchParams.get('url')
    if (!url) return json({ error: 'missing url' }, 400)

    const resource = extractResource(url)
    if (!resource) return json({ error: 'not a tidal resource url' }, 400)

    const token = await getAccessToken()
    if (!token) return json({ error: 'auth failed' }, 502)

    const data = await fetchResource(resource.type, resource.id, token)
    if (!data) return json({ error: 'lookup failed' }, 502)

    const result = toArtistWork(resource.type, data)
    if (!result) return json({ error: 'incomplete resource' }, 502)

    return json(result)
  } catch (e) {
    console.error(`tidal-resolve: ${e}`)
    return json({ error: 'internal error' }, 500)
  }
})
