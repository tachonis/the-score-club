// Admin-only Web Push broadcast sender.
//
// The gateway verifies that a JWT is present, but that alone is not enough:
// the anonymous key is also a valid JWT. Every request is therefore resolved
// to a real user and rejected unless that user is an active administrator.

import { createClient } from 'npm:@supabase/supabase-js@2'
import * as webpush from 'jsr:@negrel/webpush@0.5.0'
import {
  decodeBase64Url,
  encodeBase64Url,
} from 'jsr:@std/encoding@1/base64url'

const allowedDestinations = [
  'home',
  'predictions',
  'standings',
  'league-phase',
  'rules',
]

const allowedFields = ['title', 'message', 'destination']

const titleLimit = 80
const messageLimit = 250
const rateLimitWindowMinutes = 15
const rateLimitMaxBroadcasts = 5
const sendBatchSize = 8

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const jsonResponse = (status: number, payload: unknown) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

const requiredEnv = (name: string) => {
  const value = Deno.env.get(name)

  if (!value) {
    throw new Error(`Missing ${name}`)
  }

  return value
}

const buildVapidKeys = async () => {
  const rawPublicKey = decodeBase64Url(requiredEnv('VAPID_PUBLIC_KEY'))

  if (rawPublicKey.length !== 65 || rawPublicKey[0] !== 4) {
    throw new Error('VAPID_PUBLIC_KEY is not an uncompressed P-256 point')
  }

  const x = encodeBase64Url(rawPublicKey.slice(1, 33))
  const y = encodeBase64Url(rawPublicKey.slice(33, 65))

  return await webpush.importVapidKeys(
    {
      publicKey: {
        kty: 'EC',
        crv: 'P-256',
        x,
        y,
        ext: true,
        key_ops: ['verify'],
      },
      privateKey: {
        kty: 'EC',
        crv: 'P-256',
        x,
        y,
        d: requiredEnv('VAPID_PRIVATE_KEY'),
        ext: true,
        key_ops: ['sign'],
      },
    },
    { extractable: false },
  )
}

type BroadcastRequest = {
  title: string
  message: string
  destination: string
}

const readRequest = (payload: unknown): BroadcastRequest | string => {
  if (typeof payload !== 'object' || payload === null) {
    return 'A notification payload is required'
  }

  const body = payload as Record<string, unknown>
  const unknownField = Object.keys(body).find(
    (field) => !allowedFields.includes(field),
  )

  if (unknownField) {
    return `Unsupported field: ${unknownField}`
  }

  const title = typeof body.title === 'string' ? body.title.trim() : ''
  const message = typeof body.message === 'string' ? body.message.trim() : ''
  const destination =
    typeof body.destination === 'string' ? body.destination : ''

  if (title.length < 1 || title.length > titleLimit) {
    return `The title must be between 1 and ${titleLimit} characters`
  }

  if (message.length < 1 || message.length > messageLimit) {
    return `The message must be between 1 and ${messageLimit} characters`
  }

  if (!allowedDestinations.includes(destination)) {
    return 'An allowed destination is required'
  }

  return { title, message, destination }
}

const readPushStatus = (error: unknown) => {
  const response = (error as { response?: { status?: number } }).response

  return typeof response?.status === 'number' ? response.status : 0
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' })
  }

  const authorization = request.headers.get('Authorization') ?? ''
  const token = authorization.replace(/^Bearer\s+/i, '').trim()

  if (token === '') {
    return jsonResponse(401, { error: 'Authentication is required' })
  }

  const admin = createClient(
    requiredEnv('SUPABASE_URL'),
    requiredEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { persistSession: false } },
  )

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user ?? null

  if (userError || !user) {
    return jsonResponse(401, { error: 'Authentication is required' })
  }

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('id, role, status')
    .eq('id', user.id)
    .maybeSingle()

  if (profileError) {
    return jsonResponse(500, { error: 'The account could not be verified' })
  }

  if (!profile || profile.role !== 'admin' || profile.status !== 'active') {
    return jsonResponse(403, {
      error: 'Active administrator privileges are required',
    })
  }

  let payload: unknown

  try {
    payload = await request.json()
  } catch {
    return jsonResponse(400, { error: 'A notification payload is required' })
  }

  const parsed = readRequest(payload)

  if (typeof parsed === 'string') {
    return jsonResponse(400, { error: parsed })
  }

  const windowStart = new Date(
    Date.now() - rateLimitWindowMinutes * 60 * 1000,
  ).toISOString()

  const { count: recentCount, error: rateLimitError } = await admin
    .from('push_broadcasts')
    .select('id', { count: 'exact', head: true })
    .eq('sent_by', profile.id)
    .gte('created_at', windowStart)

  if (rateLimitError) {
    return jsonResponse(500, { error: 'The send limit could not be checked' })
  }

  if ((recentCount ?? 0) >= rateLimitMaxBroadcasts) {
    return jsonResponse(429, {
      error:
        `Up to ${rateLimitMaxBroadcasts} broadcasts are allowed every ` +
        `${rateLimitWindowMinutes} minutes`,
    })
  }

  const { data: subscriptions, error: subscriptionsError } = await admin.rpc(
    'get_active_push_subscriptions',
  )

  if (subscriptionsError) {
    return jsonResponse(500, {
      error: 'The subscribed devices could not be read',
    })
  }

  const devices = (subscriptions ?? []) as Array<{
    subscription_id: string
    endpoint: string
    p256dh: string
    auth_secret: string
  }>

  let applicationServer: webpush.ApplicationServer

  try {
    applicationServer = await webpush.ApplicationServer.new({
      contactInformation: requiredEnv('VAPID_SUBJECT'),
      vapidKeys: await buildVapidKeys(),
    })
  } catch {
    return jsonResponse(500, {
      error: 'The push credentials are missing or invalid',
    })
  }

  const notification = JSON.stringify({
    title: parsed.title,
    body: parsed.message,
    destination: parsed.destination,
  })

  const goneIds: string[] = []
  let delivered = 0
  let failed = 0

  for (let index = 0; index < devices.length; index += sendBatchSize) {
    const batch = devices.slice(index, index + sendBatchSize)

    await Promise.all(
      batch.map(async (device) => {
        try {
          await applicationServer
            .subscribe({
              endpoint: device.endpoint,
              keys: { p256dh: device.p256dh, auth: device.auth_secret },
            })
            .pushTextMessage(notification, {
              ttl: 86400,
              urgency: webpush.Urgency.High,
            })

          delivered += 1
        } catch (sendError) {
          const status = readPushStatus(sendError)

          // 404 and 410 mean the browser threw the subscription away.
          // Anything else, including 429, may still be deliverable later.
          if (status === 404 || status === 410) {
            goneIds.push(device.subscription_id)
            return
          }

          failed += 1
        }
      }),
    )
  }

  if (goneIds.length > 0) {
    await admin.from('push_subscriptions').delete().in('id', goneIds)
  }

  await admin.from('push_broadcasts').insert({
    sent_by: profile.id,
    title: parsed.title,
    body: parsed.message,
    destination: parsed.destination,
    attempted_count: devices.length,
    success_count: delivered,
    gone_count: goneIds.length,
    error_count: failed,
  })

  return jsonResponse(200, {
    attempted: devices.length,
    delivered,
    gone: goneIds.length,
    failed,
  })
})
