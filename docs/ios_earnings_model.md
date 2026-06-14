# Modèle de gains iOS — design (comparable à Android)

> Objectif : un enfant iOS gagne **le même montant** qu'un enfant Android au
> comportement équivalent, pour que tout couple parent/enfant (Android↔iOS)
> voie des chiffres cohérents. Statut : **design à valider** (non implémenté).

## 1. Rappel du modèle Android (source de vérité)

- Le service natif enregistre des **sessions écran-ÉTEINT** (`screen_sessions`,
  `start_at`/`end_at`).
- Trigger `calculate_earnings_from_session` à l'insert :
  - durée **effective** = chevauchement de la session avec la **plage active**
    du jour (`active_hours_start`→`active_hours_end`, gère minuit) ;
  - `bonus = floor(secondes_eff / 3600 × hourly_rate_cents)` ;
  - **plafond journalier** : somme des gains des sessions du même jour ≤
    `daily_max_cents`.
- Balance / bonus hebdo / payout = **somme de `earnings.amount_cents`**
  (agnostique plateforme). Socle `base_weekly_cents` ajouté à part. Plafond
  hebdo `weekly_max_cents` = `daily_max_cents` × 7 (donc déjà couvert par le
  plafond journalier).

**Unité de récompense = minutes d'écran ÉTEINT pendant la plage active.**

## 2. Ce que iOS sait mesurer

- Via Family Controls + extension `DeviceActivityMonitor` : **minutes d'usage**
  (écran ALLUMÉ), par seuils, écrites dans l'App Group.
- ⚠️ iOS mesure l'inverse d'Android (utilisé vs éteint).

### Décision retenue (implémentée)
On garde la mesure sur la **journée entière** (00:00–23:59) car elle alimente
AUSSI la carte « temps d'écran » du parent (qui veut l'usage complet). C'est la
**RPC qui clampe** l'usage à la fenêtre active (`least(used, W)`), donc
`U = usage journalier complet` en entrée, `U_window = min(U, W)` côté serveur.
Formule §3 inchangée.

### Amélioration future (différée)
Scoper le `DeviceActivitySchedule` sur la plage active pour mesurer directement
`U_window` (au lieu de clamper un total journalier). Plus précis si l'enfant
utilise beaucoup le tel hors plage, mais nécessiterait soit un 2e planning pour
la carte parent, soit d'accepter une carte « temps d'écran » partielle.
Différé.

## 3. Conversion (le cœur)

Pour un jour donné :

```
W            = durée de la plage active en minutes (gère le passage minuit)
U_window     = minutes d'usage mesurées DANS la plage active (iOS)
off_equiv    = max(0, W − U_window)        // minutes "écran éteint" équivalentes
bonus_cents  = floor(off_equiv / 60 × hourly_rate_cents)
bonus_cents  = min(bonus_cents, daily_max_cents)   // même plafond journalier
```

- Usage nul dans la plage → `off_equiv = W` → bonus max (plafonné jour).
- Usage ≥ W → `off_equiv = 0` → pas de bonus.
- **Même formule, même config, même plafond** qu'Android.

## 4. Implémentation backend recommandée

### Schéma
`earnings.session_id` est **déjà nullable**. Ajouter deux colonnes :
- `source text not null default 'android'` — `'android'` | `'ios'`
- `day date null` — jour réglé (pour iOS, idempotence)

(Les gains Android gardent `source='android'`, `day=null` : zéro impact.)

### RPC de règlement journalier (SECURITY DEFINER)
`settle_ios_screen_time(p_child_id uuid, p_day date, p_used_window_minutes int)` :
1. charge la config ; calcule `W` (plage active), `off_equiv`, `bonus_cents`
   (formule §3) ;
2. **idempotent** : `delete from earnings where child_id=p_child_id and
   source='ios' and day=p_day;` puis `insert ... (child_id, amount_cents, source,
   day) values (..., bonus_cents, 'ios', p_day)` si `bonus_cents > 0`.

Appelée par l'app enfant iOS à chaque refresh, pour aujourd'hui (et la veille au
premier refresh du jour, pour figer définitivement). Recalcule proprement au fil
de la journée (delete+insert) sans double comptage.

### Pourquoi ce choix
- **Une seule sémantique de montant** côté `earnings` → balance, bonus hebdo,
  payout, vue parent **inchangés** et identiques quelle que soit la plateforme.
- Pas de fausses `screen_sessions` (qui poseraient des soucis de recalcul
  intra-journée avec le trigger qui ne se déclenche qu'à l'insert).
- Le plafond hebdo reste assuré par le plafond journalier (×7), comme Android.

## 5. Côté app (Dart, iOS only, additif)
- `child_home` iOS : après mesure, appeler `settle_ios_screen_time(childId,
  today, U_window)` (et hier une fois par jour). Découplé du natif Android.
- Affichage : la carte gains et la balance utilisent déjà la somme des
  `earnings` → rien à changer. La carte « temps d'écran » (parent) lit déjà
  `screen_time_daily` → marche pour enfant iOS.

## 6. Limites / honnêteté
- Granularité iOS = pas des seuils (ex. 5 min) → bonus arrondi par tranches.
- `U_window` suppose la mesure scoping plage active (cf §2) ; sinon léger biais
  si l'enfant utilise beaucoup le tel hors plage.
- À valider sur **iPhone physique** (Family Controls non testable en simulateur
  ni sur device cloud type BrowserStack).

## 7. Points à confirmer avant implémentation
- [ ] Où exactement le socle `base_weekly_cents` est ajouté (UI) — vérifier que
      l'ajout est bien platform-agnostic (a priori oui).
- [ ] Comportement souhaité « hier » : figer à minuit côté serveur (cron) ou au
      premier lancement du lendemain (plus simple, retenu ici).
- [ ] Garder `source`/`day` ou suffira-t-il de `session_id is null` ? (colonnes
      explicites = plus sûr pour l'idempotence.)
