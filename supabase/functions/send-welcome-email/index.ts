import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const FROM = 'Tiipee <noreply@tiipee.com>'

serve(async (req) => {
  try {
    const { name, email } = await req.json()
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: FROM,
        to: email,
        subject: 'Bienvenue sur Tiipee 👋',
        html: `<div style="font-family:-apple-system,sans-serif;max-width:520px;margin:0 auto;padding:32px 24px;background:#0A1A0E;color:#E8F5E9;border-radius:16px;"><h2 style="margin:0 0 16px;color:#81C784;font-size:22px;">Bienvenue sur Tiipee 👋</h2><p style="margin:0 0 12px;font-size:15px;line-height:1.6;">Bonjour <strong>${name}</strong>,</p><p style="margin:0 0 12px;font-size:15px;line-height:1.6;">Votre compte parent est prêt. Vous pouvez maintenant créer le profil de votre enfant et configurer ses règles de récompense.</p><p style="margin:0 0 12px;font-size:15px;line-height:1.6;">Votre <strong>essai gratuit de 14 jours</strong> commence maintenant — aucune carte requise.</p><p style="margin:0;color:#4CAF50;font-size:12px;">— L'équipe Tiipee</p></div>`,
      }),
    })
    if (!res.ok) console.error('Resend error:', await res.text())
    return new Response(JSON.stringify({ ok: res.ok }), { headers: { 'Content-Type': 'application/json' } })
  } catch (e) {
    console.error(e)
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})
