import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  return Array.from({ length: 6 }, () =>
    chars[Math.floor(Math.random() * chars.length)]
  ).join('')
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return new Response('Unauthorized', { status: 401 })

  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } =
    await supabase.auth.getUser(token)

  if (authError || !user) return new Response('Unauthorized', { status: 401 })

  // Vérifie que l'appelant est un parent
  const { data: parentProfile } = await supabase
    .from('users')
    .select('role, family_id')
    .eq('id', user.id)
    .single()

  if (parentProfile?.role !== 'parent') {
    return new Response('Forbidden', { status: 403 })
  }

  const { name } = await req.json()
  if (!name) return new Response('Missing name', { status: 400 })

  // Génère un code unique
  let inviteCode = generateInviteCode()
  let attempts = 0
  while (attempts < 5) {
    const { data: existing } = await supabase
      .from('users')
      .select('id')
      .eq('invite_code', inviteCode)
      .maybeSingle()
    if (!existing) break
    inviteCode = generateInviteCode()
    attempts++
  }

  // Crée un auth user "fantôme" pour l'enfant
  // L'enfant le revendiquera en définissant son email/mot de passe via join-family
  const { data: childAuth, error: createError } =
    await supabase.auth.admin.createUser({
      email: `child-${inviteCode.toLowerCase()}@tiipee.internal`,
      password: crypto.randomUUID(),
      user_metadata: { role: 'child', name },
      email_confirm: true,
    })

  if (createError || !childAuth.user) {
    return new Response(JSON.stringify({ error: createError?.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // Crée le profil dans la même famille que le parent
  await supabase.from('users').insert({
    id: childAuth.user.id,
    family_id: parentProfile.family_id,
    role: 'child',
    name,
    invite_code: inviteCode,
  })

  return new Response(JSON.stringify({ inviteCode }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
