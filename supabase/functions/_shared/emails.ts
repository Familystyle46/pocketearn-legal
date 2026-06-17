// Templates email Tiipee — partagés entre toutes les Edge Functions

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const FROM = 'Tiipee <noreply@tiipee.com>'

const baseStyle = `
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  max-width: 520px; margin: 0 auto; padding: 32px 24px;
  background: #0A1A0E; color: #E8F5E9; border-radius: 16px;
`
const h2Style = `margin: 0 0 16px; color: #81C784; font-size: 22px;`
const pStyle = `margin: 0 0 12px; font-size: 15px; line-height: 1.6;`
const mutedStyle = `margin: 0; color: #4CAF50; font-size: 12px;`
const ctaStyle = `
  display: inline-block; margin-top: 20px;
  background: #2E7D32; color: white; text-decoration: none;
  padding: 14px 28px; border-radius: 12px;
  font-weight: 700; font-size: 15px;
`

export async function sendEmail(to: string, subject: string, html: string) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: FROM, to, subject, html }),
  })
  if (!res.ok) console.error('Resend error:', await res.text())
  return res.ok
}

// ── Templates ─────────────────────────────────────────────────────────────────

export function welcomeParentHtml(name: string) {
  return `<div style="${baseStyle}">
    <h2 style="${h2Style}">Bienvenue sur Tiipee 👋</h2>
    <p style="${pStyle}">Bonjour <strong>${name}</strong>,</p>
    <p style="${pStyle}">
      Votre compte parent est prêt. Vous pouvez maintenant créer le profil de votre enfant
      et configurer ses règles de récompense.
    </p>
    <p style="${pStyle}">
      Votre <strong>essai gratuit de 14 jours</strong> commence maintenant — aucune carte requise.
    </p>
    <p style="${mutedStyle}">— L'équipe Tiipee</p>
  </div>`
}

export function childJoinedHtml(parentName: string, childName: string) {
  return `<div style="${baseStyle}">
    <h2 style="${h2Style}">🎉 ${childName} a rejoint Tiipee !</h2>
    <p style="${pStyle}">Bonjour <strong>${parentName}</strong>,</p>
    <p style="${pStyle}">
      <strong>${childName}</strong> vient d'activer son compte.
      Vous pouvez maintenant suivre ses progrès et configurer ses récompenses.
    </p>
    <p style="${mutedStyle}">— L'équipe Tiipee</p>
  </div>`
}

export function subscriptionConfirmedHtml(name: string, plan: string) {
  return `<div style="${baseStyle}">
    <h2 style="${h2Style}">✅ Abonnement activé</h2>
    <p style="${pStyle}">Bonjour <strong>${name}</strong>,</p>
    <p style="${pStyle}">
      Votre abonnement <strong>${plan}</strong> est actif.
      Merci de faire confiance à Tiipee pour motiver vos enfants 💚
    </p>
    <p style="${pStyle}">
      Vos données et configurations sont conservées. L'accès premium est immédiat.
    </p>
    <p style="${mutedStyle}">— L'équipe Tiipee</p>
  </div>`
}

export function paymentFailedHtml(name: string) {
  return `<div style="${baseStyle}">
    <h2 style="${h2Style}">⚠️ Problème de paiement</h2>
    <p style="${pStyle}">Bonjour <strong>${name}</strong>,</p>
    <p style="${pStyle}">
      Nous n'avons pas pu renouveler votre abonnement Tiipee.
      Ne vous inquiétez pas — votre accès est maintenu pendant quelques jours.
    </p>
    <p style="${pStyle}">
      Mettez à jour votre moyen de paiement dans les paramètres de votre
      <strong>App Store</strong> ou <strong>Google Play Store</strong>.
    </p>
    <p style="${mutedStyle}">— L'équipe Tiipee</p>
  </div>`
}

export function accessSuspendedHtml(name: string) {
  return `<div style="${baseStyle}">
    <h2 style="${h2Style}">🔒 Accès suspendu</h2>
    <p style="${pStyle}">Bonjour <strong>${name}</strong>,</p>
    <p style="${pStyle}">
      Suite à un problème de paiement non résolu, votre accès premium a été suspendu.
    </p>
    <p style="${pStyle}">
      <strong>Vos données et celles de vos enfants sont conservées.</strong>
      Mettez à jour votre paiement pour réactiver immédiatement votre accès.
    </p>
    <p style="${mutedStyle}">— L'équipe Tiipee</p>
  </div>`
}
