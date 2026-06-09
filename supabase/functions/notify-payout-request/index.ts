import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const FIREBASE_SA = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!)
const FCM_PROJECT_ID = 'tiipee-f0b08'

// ── Génère un token OAuth2 depuis le service account Firebase ─────────────────
async function getFCMAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: FIREBASE_SA.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const b64url = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')

  const unsigned = `${b64url(header)}.${b64url(payload)}`

  const keyData = FIREBASE_SA.private_key
    .replace(/-----BEGIN PRIVATE KEY-----\n?/, '')
    .replace(/-----END PRIVATE KEY-----\n?/, '')
    .replace(/\n/g, '')

  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsigned),
  )

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')

  const jwt = `${unsigned}.${sigB64}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json()
  if (!data.access_token) throw new Error(`FCM token error: ${JSON.stringify(data)}`)
  return data.access_token
}

// ── Envoi push FCM ────────────────────────────────────────────────────────────
async function sendPush(fcmToken: string, childName: string, amount: string) {
  const accessToken = await getFCMAccessToken()
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: {
            title: '💰 Demande de versement',
            body: `${childName} demande ${amount}€`,
          },
          android: {
            notification: {
              channel_id: 'tiipee_payouts',
              icon: 'ic_notification',
            },
          },
        },
      }),
    },
  )
  if (!res.ok) {
    const err = await res.text()
    console.error('FCM error:', err)
  }
  return res.ok
}

// ── Envoi email Resend ────────────────────────────────────────────────────────
async function sendEmail(parentEmail: string, childName: string, amount: string) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Tiipee <noreply@tiipee.com>',
      to: parentEmail,
      subject: `💰 ${childName} demande son versement de ${amount}€`,
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    max-width: 480px; margin: 0 auto; padding: 32px 24px;
                    background: #0A1A0E; color: #E8F5E9; border-radius: 16px;">
          <h2 style="margin: 0 0 16px; color: #81C784; font-size: 22px;">
            Demande de versement 💰
          </h2>
          <p style="margin: 0 0 12px; font-size: 16px;">
            <strong>${childName}</strong> vient de demander son versement de
            <strong style="color: #81C784;">${amount}€</strong>.
          </p>
          <p style="margin: 0 0 24px; color: #A5D6A7; font-size: 14px;">
            Ouvrez l'app Tiipee pour valider le versement.
          </p>
          <p style="margin: 0; color: #4CAF50; font-size: 12px;">— L'équipe Tiipee</p>
        </div>
      `,
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    console.error('Resend error:', err)
  }
  return res.ok
}

// ── Handler principal ─────────────────────────────────────────────────────────
serve(async (req) => {
  try {
    const { childId, childName, amountCents, parentId } = await req.json()

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Récupère infos parent
    const { data: parent, error } = await supabase
      .from('users')
      .select('email, fcm_token, name')
      .eq('id', parentId)
      .single()

    if (error || !parent) {
      return new Response(JSON.stringify({ error: 'Parent introuvable' }), { status: 404 })
    }

    const amount = (amountCents / 100).toFixed(2).replace('.', ',')
    const results: Record<string, unknown> = {}

    // Push FCM
    if (parent.fcm_token) {
      results.push = await sendPush(parent.fcm_token, childName, amount)
    } else {
      results.push = 'no_token'
    }

    // Email Resend
    if (parent.email) {
      results.email = await sendEmail(parent.email, childName, amount)
    } else {
      results.email = 'no_email'
    }

    return new Response(JSON.stringify(results), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error(e)
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})
