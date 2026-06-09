/**
 * activate-child
 *
 * Flux : l'enfant a entré le code invite → on a trouvé le profil placeholder.
 * Cette fonction :
 *   1. Met à jour l'email + mot de passe du compte auth fantôme
 *   2. Connecte l'enfant et renvoie la session
 *
 * Body attendu : { inviteCode: string, email: string, password: string }
 * Réponse      : { access_token, refresh_token, user }
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: { inviteCode?: string; email?: string; password?: string }
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const { inviteCode, email, password } = body

  if (!inviteCode || !email || !password) {
    return new Response(
      JSON.stringify({ error: 'inviteCode, email and password are required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    )
  }

  if (password.length < 8) {
    return new Response(
      JSON.stringify({ error: 'Le mot de passe doit faire au moins 8 caractères' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 1. Retrouver le profil enfant via le code invite
  const { data: childProfile, error: lookupError } = await supabaseAdmin
    .from('users')
    .select('id, name')
    .eq('invite_code', inviteCode.toUpperCase())
    .maybeSingle()

  if (lookupError || !childProfile) {
    return new Response(
      JSON.stringify({ error: 'Code invalide ou expiré' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 2. Vérifier que l'email n'est pas déjà pris par un autre compte
  const { data: existingUser } = await supabaseAdmin
    .from('users')
    .select('id')
    .eq('id', childProfile.id)
    .maybeSingle()

  if (!existingUser) {
    return new Response(
      JSON.stringify({ error: 'Profil enfant introuvable' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 3. Mettre à jour le compte auth fantôme avec le vrai email + mot de passe
  const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
    childProfile.id,
    {
      email,
      password,
      email_confirm: true, // confirme directement, pas d'email de validation
    },
  )

  if (updateError) {
    // Si l'email est déjà utilisé par un autre compte, erreur claire
    return new Response(
      JSON.stringify({ error: updateError.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 4. Supprimer le code invite pour qu'il ne puisse plus être réutilisé
  await supabaseAdmin
    .from('users')
    .update({ invite_code: null })
    .eq('id', childProfile.id)

  // 5. Connecter l'enfant et renvoyer la session
  const { data: sessionData, error: signInError } =
    await supabaseAdmin.auth.signInWithPassword({ email, password })

  if (signInError || !sessionData.session) {
    return new Response(
      JSON.stringify({ error: 'Compte créé mais connexion échouée — réessaie' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }

  return new Response(
    JSON.stringify({
      access_token: sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      user: {
        id: sessionData.user!.id,
        name: childProfile.name,
      },
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  )
})
