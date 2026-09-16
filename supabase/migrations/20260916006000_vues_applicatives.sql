-- 20260916006000_vues_applicatives.sql
--
-- Ce que les trois écrans du MVP consomment directement.
--
-- Pourquoi des vues plutôt que des jointures côté client : l'application
-- Flutter parle à PostgREST, qui ne sait pas joindre deux vues. Sans cela,
-- chaque écran ferait deux ou trois requêtes puis recomposerait le résultat en
-- Dart, ce qui déplacerait de la logique métier dans le client, la dupliquerait
-- entre Android et un éventuel iOS, et finirait par diverger de la base.
--
-- Toutes sont en `security_invoker` : elles s'exécutent avec les droits de
-- l'appelant, donc les politiques RLS s'appliquent et chacun ne voit que son
-- périmètre. Sans cette option, une vue contourne silencieusement RLS.

-- ── 1. Le carnet de courses du distributeur ────────────────────────────────
--
-- Reprend l'écran « Courses » de la maquette : les deux cercles, et le temps
-- restant avant que la course ne s'ouvre aux confrères. Ce compte à rebours est
-- calculé ici, à partir de `delai_escalade()`, et non dans l'application : le
-- délai doit pouvoir changer par un simple CREATE OR REPLACE sans qu'il faille
-- republier un APK.

CREATE VIEW v_carnet_distributeur
WITH (security_invoker = on) AS
SELECT
  acc.distributeur_id,
  acc.cercle,
  ro.rupture_id,
  ro.point_de_vente_id,
  ro.point_de_vente_nom,
  ro.commune,
  ro.produit_id,
  ro.produit_nom,
  ro.fabricant_id,
  f.nom            AS fabricant_nom,
  r.quantite_demandee,
  ro.statut,
  ro.signalement_automatique,
  ro.date_signalement,
  ro.escaladee_le,
  ro.livreur_id,
  -- Temps restant avant ouverture au cercle élargi. Négatif ou nul = déjà ouvert.
  GREATEST(
    EXTRACT(EPOCH FROM (ro.date_signalement + delai_escalade() - now()))::INTEGER,
    0
  ) AS secondes_avant_escalade,
  EXTRACT(EPOCH FROM (now() - ro.date_signalement))::INTEGER AS anciennete_secondes
FROM v_acces_rupture_distributeur acc
JOIN v_ruptures_ouvertes ro ON ro.rupture_id = acc.rupture_id
JOIN ruptures r             ON r.id = ro.rupture_id
JOIN fabricants f           ON f.id = ro.fabricant_id;

COMMENT ON VIEW v_carnet_distributeur IS
  'Écran Courses du distributeur. Filtré par RLS : chacun n''y voit que son périmètre.';

-- ── 2. Les courses à proximité du livreur ──────────────────────────────────
--
-- Une fonction et non une vue, parce que le tri dépend d'un point de référence :
-- la position du livreur, qui change à chaque requête.
--
-- STABLE et non SECURITY DEFINER : elle doit rester soumise à RLS, pour qu'un
-- livreur ne puisse pas lire les ruptures hors du périmètre de son distributeur
-- en appelant la fonction directement.

CREATE OR REPLACE FUNCTION courses_a_proximite(p_limite INTEGER DEFAULT 20)
RETURNS TABLE (
  rupture_id         UUID,
  point_de_vente_nom TEXT,
  commune            TEXT,
  produit_nom        TEXT,
  quantite_demandee  INTEGER,
  cercle             TEXT,
  date_signalement   TIMESTAMPTZ,
  distance_metres    DOUBLE PRECISION
)
LANGUAGE sql STABLE AS $fn$
  SELECT ro.rupture_id,
         ro.point_de_vente_nom,
         ro.commune,
         ro.produit_nom,
         r.quantite_demandee,
         acc.cercle,
         ro.date_signalement,
         ST_Distance(ro.position, l.position) AS distance_metres
    FROM v_ruptures_ouvertes ro
    JOIN v_acces_rupture_distributeur acc ON acc.rupture_id = ro.rupture_id
    JOIN ruptures r  ON r.id = ro.rupture_id
    JOIN livreurs l  ON l.id = auth_id_metier()
                    AND l.distributeur_id = acc.distributeur_id
   WHERE ro.statut = 'signalee'
   ORDER BY ro.position <-> l.position
   LIMIT p_limite;
$fn$;

COMMENT ON FUNCTION courses_a_proximite IS
  'Ruptures que le livreur connecté peut prendre, triées par distance réelle (PostGIS).';

REVOKE EXECUTE ON FUNCTION courses_a_proximite FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION courses_a_proximite TO authenticated;

-- ── 3. Le stock du point de vente, avec le nom du produit ──────────────────
--
-- La table `stocks` ne porte qu'un identifiant de produit. L'ancienne API
-- renvoyait le stock sans jointure, donc sans nom : un écran inutilisable.

CREATE VIEW v_stock_point_de_vente
WITH (security_invoker = on) AS
SELECT
  s.point_de_vente_id,
  s.produit_id,
  COALESCE(p.nom, s.produit_libre_nom) AS produit_nom,
  p.reference,
  f.nom AS fabricant_nom,
  c.nom AS categorie_nom,
  s.quantite,
  s.date_maj,
  (s.quantite <= 0) AS en_rupture
FROM stocks s
LEFT JOIN produits p           ON p.id = s.produit_id
LEFT JOIN fabricants f         ON f.id = p.fabricant_id
LEFT JOIN categories_produit c ON c.id = p.categorie_id;

COMMENT ON VIEW v_stock_point_de_vente IS
  'Écran Stock du point de vente. Privé : RLS ne laisse passer que ses propres lignes.';
