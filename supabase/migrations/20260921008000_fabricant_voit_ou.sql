-- 20260921008000_fabricant_voit_ou.sql
--
-- Le fabricant voyait ses ruptures sans savoir où elles étaient.
--
-- ── LE DÉFAUT, ET DEPUIS QUAND ──────────────────────────────────────────────
--
-- `ruptures_fabricant` lui donnait bien accès à ses ruptures. Mais aucune
-- politique ne lui permettait de lire `points_de_vente`, et toutes les vues qui
-- présentent une rupture la JOIGNENT au point de vente pour en afficher le nom
-- et la commune.
--
-- Or une jointure interne sur une table dont RLS ne rend aucune ligne SUPPRIME
-- LA LIGNE ENTIÈRE. Le fabricant ne voyait donc pas « une rupture sans nom de
-- boutique » : il ne voyait RIEN. `v_ruptures_ouvertes` lui rendait zéro ligne
-- alors que trois ruptures de son catalogue étaient ouvertes.
--
-- Aucune erreur, aucun refus, un tableau vide. Le défaut existait depuis que le
-- rôle fabricant a des politiques, et il annulait la promesse centrale du
-- produit : dire à un industriel où ses produits manquent.
--
-- Trouvé en interrogeant l'API avec un vrai compte fabricant, pas en relisant
-- le SQL. Les vues avaient l'air justes, et elles le sont ; c'est ce qu'elles
-- traversent qui manquait.
--
-- ── CE QUE LE FABRICANT A LE DROIT DE VOIR, ET PAS PLUS ─────────────────────
--
-- Le nom et la commune d'une boutique où SON produit manque, ou qui lui est
-- attribuée. Pas le réseau entier : la liste des points de vente d'Abidjan est
-- un actif commercial, et la donner à chaque marque reviendrait à la publier.
--
-- Et toujours pas la caisse. `ventes`, `lignes_vente` et `stocks` lui restent
-- fermées : il apprend qu'un produit manque, jamais combien la boutique vend.

CREATE POLICY pdv_fabricant ON points_de_vente FOR SELECT TO authenticated
  USING (
    auth_role() = 'fabricant'
    AND (
      -- Une boutique qui lui est attribuée : elle porte sa marque, il doit
      -- pouvoir la nommer.
      EXISTS (
        SELECT 1 FROM attributions_reseau ar
         WHERE ar.point_de_vente_id = points_de_vente.id
           AND ar.fabricant_id = auth_id_metier()
      )
      -- Ou une boutique où l'un de ses produits est en rupture. L'attribution
      -- n'est pas toujours faite au moment où la rupture naît, et c'est
      -- précisément le cas où l'information lui est la plus utile.
      OR EXISTS (
        SELECT 1 FROM ruptures r
          JOIN produits p ON p.id = r.produit_id
         WHERE r.point_de_vente_id = points_de_vente.id
           AND p.fabricant_id = auth_id_metier()
      )
    )
  );

-- Le distributeur qui sert sa marque. La jointure est externe dans les vues,
-- donc son absence n'effaçait aucune ligne : elle affichait seulement
-- « aucun distributeur » là où il y en avait un, ce qui est un mensonge plus
-- discret mais un mensonge quand même.
CREATE POLICY distributeurs_fabricant ON distributeurs FOR SELECT TO authenticated
  USING (
    auth_role() = 'fabricant'
    AND (
      fabricant_id = auth_id_metier()
      OR EXISTS (
        SELECT 1 FROM attributions_reseau ar
         WHERE ar.distributeur_id = distributeurs.id
           AND ar.fabricant_id = auth_id_metier()
      )
    )
  );

COMMENT ON POLICY pdv_fabricant ON points_de_vente IS
  'Le fabricant nomme les boutiques où sa marque est présente ou en rupture, et aucune autre. Sans cette politique, toutes les vues de rupture lui rendaient zéro ligne par effet de jointure.';
