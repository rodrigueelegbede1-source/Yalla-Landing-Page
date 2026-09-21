-- 20260921004000_supervision_carte.sql
--
-- De quoi nourrir la carte et les courbes du tableau de bord administrateur.
--
-- ── POURQUOI UNE CARTE POUR L'ADMINISTRATEUR ────────────────────────────────
--
-- Le réseau de Yalla est un objet géographique avant d'être un tableau. Une
-- liste de boutiques triées par commune ne dit pas ce qu'un point sur une carte
-- dit en une seconde : que trois boutiques recensées sont collées les unes aux
-- autres pendant qu'une commune entière est vide, ou qu'une boutique orpheline
-- se trouve à deux rues d'un distributeur qui pourrait la servir.
--
-- Les positions existent déjà : l'agent recenseur les relève sur le pas de la
-- porte, à moins de vingt-cinq mètres. Elles ne sortaient simplement pas de la
-- vue.
--
-- ── CE QUE CELA N'OUVRE PAS ─────────────────────────────────────────────────
--
-- La position d'une boutique, non son commerce. L'administrateur voit où elle
-- est, combien de références elle suit et combien de ruptures elle a ouvertes.
-- Ni ce qu'elle vend, ni ce qu'elle encaisse : `ventes` et `lignes_vente` lui
-- restent fermées, comme à tout le monde sauf au boutiquier.

-- ── 1. La position des boutiques ────────────────────────────────────────────
--
-- Les deux colonnes sont ajoutées EN FIN de vue : `CREATE OR REPLACE VIEW`
-- n'autorise qu'un ajout en queue, jamais un réordonnancement.
--
-- L'option `security_invoker` est redéclarée explicitement. Un `CREATE OR
-- REPLACE VIEW` qui l'omet la remet silencieusement à sa valeur par défaut,
-- c'est-à-dire que la vue se mettrait à contourner RLS pour tout le monde. Le
-- harnais de tests refuse toute vue sans cette option, précisément pour ça.

CREATE OR REPLACE VIEW v_supervision_boutiques
WITH (security_invoker = on) AS
SELECT
  pdv.id AS point_de_vente_id,
  pdv.nom,
  pdv.commune,
  pdv.type_activite,
  pdv.statut,
  pdv.gerant_nom,
  pdv.telephone,
  pdv.created_at,
  u.nom AS agent_recenseur,
  (SELECT count(*) FROM stocks s WHERE s.point_de_vente_id = pdv.id) AS references_suivies,
  (SELECT count(*) FROM ruptures r
    WHERE r.point_de_vente_id = pdv.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS ruptures_ouvertes,
  (SELECT string_agg(DISTINCT f.nom, ', ')
     FROM attributions_reseau ar JOIN fabricants f ON f.id = ar.fabricant_id
    WHERE ar.point_de_vente_id = pdv.id) AS marques,
  (SELECT string_agg(DISTINCT d.nom, ', ')
     FROM attributions_reseau ar JOIN distributeurs d ON d.id = ar.distributeur_id
    WHERE ar.point_de_vente_id = pdv.id) AS distributeurs,
  ST_Y(pdv.position::GEOMETRY) AS latitude,
  ST_X(pdv.position::GEOMETRY) AS longitude
FROM points_de_vente pdv
LEFT JOIN agents_recenseurs a ON a.id = pdv.agent_recenseur_id
LEFT JOIN utilisateurs u ON u.id = a.utilisateur_id;

-- ── 2. L'activité des quatorze derniers jours ───────────────────────────────
--
-- POURQUOI QUATORZE JOURS, et pas trente ni sept. Sept ne laissent pas voir
-- l'effet d'un week-end, trente écrasent la courbe sur un pilote qui n'a que
-- quelques ruptures par jour. Deux semaines montrent le rythme hebdomadaire
-- sans noyer le signal.
--
-- POURQUOI `generate_series` PLUTÔT QU'UN `GROUP BY`. Un regroupement sur les
-- ruptures n'aurait produit que les jours où il s'est passé quelque chose, et
-- la courbe aurait relié le lundi au jeudi en sautant les jours creux, ce qui
-- est exactement le contraire de ce qu'on cherche à voir. La série fabrique
-- d'abord les quatorze jours, puis compte : un jour sans rupture vaut zéro et
-- se dessine comme tel.
--
-- Les comptages passent par des sous-requêtes corrélées plutôt que par des
-- jointures, pour que les politiques RLS de `ruptures` et `livraisons`
-- s'appliquent à chacune sans qu'une jointure externe ne laisse filtrer une
-- ligne interdite sous forme de NULL.

CREATE VIEW v_supervision_activite
WITH (security_invoker = on) AS
SELECT
  j.jour::DATE AS jour,
  (SELECT count(*) FROM ruptures r
    WHERE r.date_signalement >= j.jour
      AND r.date_signalement <  j.jour + INTERVAL '1 day') AS signalees,
  (SELECT count(*) FROM ruptures r
    WHERE r.statut = 'resolue'
      AND r.date_resolution >= j.jour
      AND r.date_resolution <  j.jour + INTERVAL '1 day') AS resolues,
  (SELECT count(*) FROM livraisons l
    WHERE l.date_debut >= j.jour
      AND l.date_debut <  j.jour + INTERVAL '1 day') AS livraisons
FROM generate_series(
       date_trunc('day', now()) - INTERVAL '13 days',
       date_trunc('day', now()),
       INTERVAL '1 day'
     ) AS j(jour);

COMMENT ON VIEW v_supervision_activite IS
  'Rythme du réseau sur quatorze jours. Les jours creux valent zéro et sont présents : c''est le creux qui informe, pas seulement le pic.';
