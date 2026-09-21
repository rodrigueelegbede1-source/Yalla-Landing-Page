-- 20260921003000_fabricant_sa_propre_ligne.sql
--
-- Un fabricant voyait la ligne de ses concurrents.
--
-- ── COMMENT LE DÉFAUT S'EST MONTRÉ ──────────────────────────────────────────
--
-- En vérifiant le tableau de bord administrateur, un compte fabricant de test
-- a été créé, puis connecté. Sa première requête sur son propre tableau de bord
-- a rendu TROIS lignes : la sienne, celle d'Ivoire Boissons et celle de
-- SDTM-CI, avec le nombre de références de chacune.
--
-- `v_tableau_de_bord_fabricant` part de `fabricants`, table volontairement
-- lisible de tous les comptes authentifiés parce que le boutiquier doit
-- pouvoir parcourir les catalogues. La vue n'ajoutait aucune restriction : les
-- colonnes agrégées, elles, restaient bien filtrées par les politiques des
-- tables traversées, mais la LIGNE et le décompte de références, non.
--
-- ── POURQUOI C'ÉTAIT PIRE QU'UNE FUITE ──────────────────────────────────────
--
-- La page `tableau-de-bord.html` lit `lignes[0]`, faute d'avoir jamais eu plus
-- d'une ligne à lire. Tant qu'il n'existait qu'un fabricant, elle avait raison.
-- Au deuxième, elle se mettait à afficher à chacun le tableau de bord du
-- premier venu, sans que rien ne le signale : un nom d'entreprise en tête de
-- page, des chiffres plausibles, et aucune erreur.
--
-- Le produit se vend au fabricant sur la promesse du taux de service de SA
-- marque. Lui montrer celui d'un concurrent, en le présentant comme le sien,
-- est la pire des deux fautes.
--
-- ── LA CORRECTION ───────────────────────────────────────────────────────────
--
-- Le filtre vit dans la vue, pas dans la page. Une restriction écrite en
-- JavaScript se contourne avec la console du navigateur ; celle-ci non, elle
-- s'applique dans la base pour tout appelant, y compris `curl`.
--
-- L'administrateur garde la vue complète : il supervise le réseau, et c'est le
-- seul rôle dont c'est le métier. Son propre écran interroge `fabricants` en
-- direct pour remplir ses sélecteurs, mais la vue lui reste ouverte.

CREATE OR REPLACE VIEW v_tableau_de_bord_fabricant
WITH (security_invoker = on) AS
SELECT
  f.id   AS fabricant_id,
  f.nom  AS fabricant_nom,
  (SELECT count(*) FROM produits p WHERE p.fabricant_id = f.id AND p.disponible) AS produits,
  (SELECT count(DISTINCT ar.point_de_vente_id)
     FROM attributions_reseau ar WHERE ar.fabricant_id = f.id) AS boutiques,
  (SELECT count(DISTINCT ar.distributeur_id)
     FROM attributions_reseau ar
    WHERE ar.fabricant_id = f.id AND ar.distributeur_id IS NOT NULL) AS distributeurs,
  (SELECT count(*)
     FROM ruptures r JOIN produits p ON p.id = r.produit_id
    WHERE p.fabricant_id = f.id AND r.statut = 'signalee'
      AND r.confirmee_le IS NOT NULL) AS ruptures_ouvertes,
  ts.ruptures_closes,
  ts.ruptures_servies,
  ts.taux_de_service_pct,
  ts.delai_moyen_prise_en_charge,
  ca.chiffre_affaires,
  ca.dont_distributeurs_non_rattaches
FROM fabricants f
LEFT JOIN v_taux_de_service_par_fabricant ts ON ts.fabricant_id = f.id
LEFT JOIN v_chiffre_affaires_genere_par_fabricant ca ON ca.fabricant_id = f.id
WHERE est_admin()
   OR (auth_role() = 'fabricant' AND f.id = auth_id_metier());

COMMENT ON VIEW v_tableau_de_bord_fabricant IS
  'Ce qu''un fabricant a besoin de voir, et rien de plus : sa seule ligne. L''administrateur, lui, voit le réseau entier. Le taux de service est l''indicateur vendu ; l''écart entre les deux mesures de chiffre d''affaires dit quelle part de sa distribution lui échappe.';
