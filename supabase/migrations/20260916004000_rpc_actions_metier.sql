-- 20260916004000_rpc_actions_metier.sql
--
-- Les actions qui écrivent passent par des fonctions, pas par des écritures
-- directes du client.
--
-- Raison : une politique RLS sait dire « tu as le droit de toucher cette ligne ».
-- Elle ne sait pas dire « seul le premier arrivé gagne », ni « ces trois écritures
-- forment un tout ». Ces règles-là vivent ici, en un seul endroit, et l'application
-- Flutter n'a qu'à les appeler.
--
-- Toutes sont SECURITY DEFINER, donc elles contournent RLS : chacune vérifie
-- donc explicitement le rôle et la propriété de la ressource, en première ligne.
-- C'est la contrepartie, et elle n'est pas négociable.
--
-- DEUX MANQUES DU BACKEND PRÉCÉDENT SONT COMBLÉS ICI :
--
--  1. Aucun code ne renseignait `attributions_reseau.distributeur_id`. Or le
--     trigger de routage ne lit que cette colonne. Toute rupture naissait donc
--     avec un destinataire nul, invisible du cercle attribué, et n'apparaissait
--     qu'après deux heures d'escalade. Le mécanisme central du produit était
--     donc inopérant. `attribuer_point_de_vente()` le corrige.
--
--  2. Aucun code ne créait ni n'ajustait de ligne de `stocks`. Or le trigger de
--     caisse sort sans rien faire s'il ne trouve pas de stock suivi
--     (`IF v_nouvelle_quantite IS NULL THEN RETURN NEW`). Sans alimentation du
--     stock, la rupture automatique ne pouvait tout simplement jamais se
--     déclencher. `reapprovisionner_stock()` le corrige.

-- ── 1. Prendre une rupture ─────────────────────────────────────────────────
--
-- Reprend mot pour mot le verrou validé côté NestJS : UPDATE conditionné sur
-- `statut = 'signalee'`, donc le premier livreur gagne et les suivants ne
-- touchent aucune ligne. Sans cette condition, deux livreurs partent sur la
-- même course en croyant chacun l'avoir obtenue.

CREATE OR REPLACE FUNCTION prendre_rupture(p_rupture_id UUID)
RETURNS ruptures
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_livreur_id      UUID := auth_id_metier();
  v_distributeur_id UUID;
  v_rupture         ruptures;
BEGIN
  IF auth_role() <> 'livreur' THEN
    RAISE EXCEPTION 'Seul un livreur peut prendre une course' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT distributeur_id INTO v_distributeur_id FROM livreurs WHERE id = v_livreur_id;
  IF v_distributeur_id IS NULL THEN
    RAISE EXCEPTION 'Livreur introuvable ou sans distributeur' USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE ruptures r
     SET statut               = 'prise_en_charge',
         livreur_id           = v_livreur_id,
         date_prise_en_charge = now()
   WHERE r.id = p_rupture_id
     AND r.statut = 'signalee'
     AND distributeur_voit_rupture(r.id, v_distributeur_id)
  RETURNING r.* INTO v_rupture;

  IF v_rupture.id IS NULL THEN
    -- Trois causes possibles, et le livreur mérite de savoir laquelle.
    SELECT * INTO v_rupture FROM ruptures WHERE id = p_rupture_id;
    IF v_rupture.id IS NULL THEN
      RAISE EXCEPTION 'Rupture introuvable' USING ERRCODE = 'no_data_found';
    ELSIF v_rupture.statut <> 'signalee' THEN
      RAISE EXCEPTION 'Cette course vient d''être prise par un autre livreur'
        USING ERRCODE = 'lock_not_available';
    ELSE
      RAISE EXCEPTION 'Cette course ne relève pas de votre distributeur'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN v_rupture;
END;
$fn$;

-- ── 2. Affecter un livreur, côté distributeur ──────────────────────────────
--
-- La maquette Distributeur porte un bouton « Prendre la course et affecter ».
-- Le backend ne l'implémentait pas : seul un livreur pouvait prendre une course.

CREATE OR REPLACE FUNCTION affecter_livreur(p_rupture_id UUID, p_livreur_id UUID)
RETURNS ruptures
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_distributeur_id UUID := auth_id_metier();
  v_rupture         ruptures;
BEGIN
  IF auth_role() <> 'distributeur' THEN
    RAISE EXCEPTION 'Seul un distributeur peut affecter un livreur' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Le livreur doit appartenir à sa flotte. Sans ce contrôle, un distributeur
  -- pourrait coller une course sur le dos du livreur d'un confrère.
  IF NOT EXISTS (SELECT 1 FROM livreurs WHERE id = p_livreur_id AND distributeur_id = v_distributeur_id) THEN
    RAISE EXCEPTION 'Ce livreur ne fait pas partie de votre flotte' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE ruptures r
     SET statut = 'prise_en_charge', livreur_id = p_livreur_id, date_prise_en_charge = now()
   WHERE r.id = p_rupture_id
     AND r.statut = 'signalee'
     AND distributeur_voit_rupture(r.id, v_distributeur_id)
  RETURNING r.* INTO v_rupture;

  IF v_rupture.id IS NULL THEN
    RAISE EXCEPTION 'Course indisponible : déjà prise, inexistante, ou hors de votre périmètre'
      USING ERRCODE = 'lock_not_available';
  END IF;

  RETURN v_rupture;
END;
$fn$;

-- ── 3. Encaisser une vente ─────────────────────────────────────────────────
--
-- Le geste central du produit. La vente et ses lignes sont créées d'un bloc ;
-- le trigger `trg_lignes_vente_decremente_stock` fait le reste, c'est-à-dire
-- décrémenter les stocks et créer la rupture si un stock tombe à zéro.
--
-- Les lignes arrivent en JSON :
--   [{"produit_id": "...", "quantite": 2, "prix_unitaire": 1200},
--    {"produit_libre_nom": "Pain", "quantite": 1, "prix_unitaire": 200}]

CREATE OR REPLACE FUNCTION enregistrer_vente(p_lignes JSONB)
RETURNS ventes
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv_id UUID := auth_id_metier();
  v_vente  ventes;
  v_total  NUMERIC(12,2);
  v_ligne  JSONB;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul un point de vente peut encaisser' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_lignes IS NULL OR jsonb_array_length(p_lignes) = 0 THEN
    RAISE EXCEPTION 'Une vente sans ligne n''a pas de sens' USING ERRCODE = 'check_violation';
  END IF;

  -- Le total est calculé en base, pas transmis par le client : un montant
  -- envoyé depuis le téléphone peut être n'importe quoi.
  SELECT COALESCE(SUM((l->>'quantite')::INTEGER * (l->>'prix_unitaire')::NUMERIC), 0)
    INTO v_total
    FROM jsonb_array_elements(p_lignes) l;

  INSERT INTO ventes (point_de_vente_id, montant_total)
  VALUES (v_pdv_id, v_total)
  RETURNING * INTO v_vente;

  FOR v_ligne IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    INSERT INTO lignes_vente (vente_id, produit_id, produit_libre_nom, quantite, prix_unitaire)
    VALUES (
      v_vente.id,
      NULLIF(v_ligne->>'produit_id', '')::UUID,
      NULLIF(v_ligne->>'produit_libre_nom', ''),
      (v_ligne->>'quantite')::INTEGER,
      (v_ligne->>'prix_unitaire')::NUMERIC
    );
  END LOOP;

  RETURN v_vente;
END;
$fn$;

-- ── 4. Alimenter le stock ──────────────────────────────────────────────────
--
-- Sans cette fonction, rien ne peut jamais tomber à zéro, donc aucune rupture
-- automatique ne se déclenche, donc le produit ne fait rien de ce qu'il promet.
-- `p_quantite` est une variation : positive à la réception d'une livraison,
-- négative à la correction d'un inventaire.

CREATE OR REPLACE FUNCTION reapprovisionner_stock(p_produit_id UUID, p_quantite INTEGER)
RETURNS stocks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pdv_id UUID := auth_id_metier();
  v_stock  stocks;
BEGIN
  IF auth_role() <> 'point_de_vente' THEN
    RAISE EXCEPTION 'Seul un point de vente gère son stock' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO stocks (point_de_vente_id, produit_id, quantite, date_maj)
  VALUES (v_pdv_id, p_produit_id, GREATEST(p_quantite, 0), now())
  ON CONFLICT (point_de_vente_id, produit_id) WHERE produit_id IS NOT NULL
  DO UPDATE SET quantite = GREATEST(stocks.quantite + p_quantite, 0),
                date_maj = now()
  RETURNING * INTO v_stock;

  RETURN v_stock;
END;
$fn$;

-- ── 5. Terminer une livraison ──────────────────────────────────────────────
--
-- Le trigger `trg_livraisons_resout_rupture` clôt la rupture liée dès que la
-- livraison passe à `terminee`. On ne le refait donc pas ici.

CREATE OR REPLACE FUNCTION terminer_livraison(p_livraison_id UUID, p_montant NUMERIC DEFAULT 0)
RETURNS livraisons
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_livreur_id UUID := auth_id_metier();
  v_livraison  livraisons;
BEGIN
  IF auth_role() <> 'livreur' THEN
    RAISE EXCEPTION 'Seul un livreur termine une livraison' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE livraisons
     SET statut = 'terminee', date_fin = now(), montant = COALESCE(p_montant, 0)
   WHERE id = p_livraison_id
     AND livreur_id = v_livreur_id      -- la propriété, que l'API ne vérifiait pas
     AND statut = 'en_cours'
  RETURNING * INTO v_livraison;

  IF v_livraison.id IS NULL THEN
    RAISE EXCEPTION 'Livraison introuvable, déjà close, ou qui ne vous appartient pas'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Trace du règlement. En espèces pour le MVP, l'intégration du paiement
  -- mobile viendra plus tard sans toucher à cette fonction.
  IF COALESCE(p_montant, 0) > 0 THEN
    INSERT INTO transactions (livraison_id, montant, fournisseur, statut)
    VALUES (v_livraison.id, p_montant, 'especes', 'confirmee');
  END IF;

  RETURN v_livraison;
END;
$fn$;

-- ── 6. Attribuer une boutique, avec son distributeur ───────────────────────
--
-- La colonne `distributeur_id` était ajoutée par la migration 011 mais jamais
-- renseignée par quoi que ce soit. C'est la fonction qui rend le routage des
-- ruptures réellement opérant.

CREATE OR REPLACE FUNCTION attribuer_point_de_vente(
  p_fabricant_id      UUID,
  p_point_de_vente_id UUID,
  p_distributeur_id   UUID
)
RETURNS attributions_reseau
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_attribution attributions_reseau;
BEGIN
  IF NOT est_admin() THEN
    RAISE EXCEPTION 'Réservé à l''administrateur du réseau' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO attributions_reseau (fabricant_id, point_de_vente_id, distributeur_id)
  VALUES (p_fabricant_id, p_point_de_vente_id, p_distributeur_id)
  ON CONFLICT (fabricant_id, point_de_vente_id)
  DO UPDATE SET distributeur_id = EXCLUDED.distributeur_id
  RETURNING * INTO v_attribution;

  RETURN v_attribution;
END;
$fn$;

-- ── 7. Droits d'exécution ──────────────────────────────────────────────────
--
-- Chaque fonction vérifie déjà le rôle en interne. On restreint tout de même
-- l'exécution aux comptes authentifiés : un visiteur anonyme n'a rien à faire ici.

REVOKE EXECUTE ON FUNCTION prendre_rupture, affecter_livreur, enregistrer_vente,
                           reapprovisionner_stock, terminer_livraison,
                           attribuer_point_de_vente
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION prendre_rupture, affecter_livreur, enregistrer_vente,
                          reapprovisionner_stock, terminer_livraison,
                          attribuer_point_de_vente
  TO authenticated;
