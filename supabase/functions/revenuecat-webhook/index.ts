import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Secret à configurer dans RevenueCat Dashboard → Webhooks → Authorization header
const WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? ''

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  // Vérifie le secret RevenueCat
  const authHeader = req.headers.get('Authorization') ?? ''
  if (WEBHOOK_SECRET && authHeader !== WEBHOOK_SECRET) {
    return new Response('Unauthorized', { status: 401 })
  }

  const payload = await req.json()
  const event = payload.event
  if (!event) return new Response('No event', { status: 400 })

  const appUserId: string = event.app_user_id
  const eventType: string = event.type
  const expiresAt: string | null = event.expiration_at_ms
    ? new Date(event.expiration_at_ms).toISOString()
    : null

  // Récupère la famille via l'userId Supabase
  const { data: user } = await supabase
    .from('users')
    .select('family_id')
    .eq('id', appUserId)
    .limit(1)
    .single()

  if (!user?.family_id) {
    console.error('Family not found for user', appUserId)
    return new Response('User not found', { status: 404 })
  }

  const familyId = user.family_id

  // Mise à jour du statut abonnement selon l'événement RevenueCat
  let status: string | null = null

  switch (eventType) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'PRODUCT_CHANGE':
      status = 'active'
      break
    case 'CANCELLATION':
    case 'EXPIRATION':
      status = 'expired'
      break
    case 'BILLING_ISSUE':
      status = 'billing_issue'
      break
    case 'UNCANCELLATION':
      status = 'active'
      break
    default:
      // NON_RENEWING_PURCHASE, TRANSFER, etc. — on ignore
      return new Response(JSON.stringify({ ignored: eventType }), { status: 200 })
  }

  const updateData: Record<string, unknown> = {
    subscription_status: status,
    revenuecat_customer_id: event.aliases?.[0] ?? appUserId,
  }
  if (expiresAt) updateData.subscription_expires_at = expiresAt

  const { error } = await supabase
    .from('families')
    .update(updateData)
    .eq('id', familyId)

  if (error) {
    console.error('Update error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  console.log(`✅ ${eventType} → famille ${familyId} → status: ${status}`)
  return new Response(JSON.stringify({ ok: true, status }), { status: 200 })
})
