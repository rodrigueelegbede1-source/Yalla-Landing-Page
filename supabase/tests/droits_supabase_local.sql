-- droits_supabase_local.sql
--
-- Accorde aux rôles `authenticated` et `anon` les mêmes droits de table que
-- Supabase leur donne par défaut. À appliquer APRÈS les migrations, puisqu'il
-- porte sur les tables qu'elles créent.
--
-- ════════════════════════════════════════════════════════════════════════════
-- POURQUOI CE FICHIER CHANGE CE QUE LA SUITE DE TESTS VAUT
-- ════════════════════════════════════════════════════════════════════════════
--
-- Jusqu'ici, les suites tournaient sous l'utilisateur propriétaire de la base,
-- et un propriétaire CONTOURNE PUREMENT ET SIMPLEMENT les politiques RLS. Tous
-- les cas écrits « tel rôle voit N lignes » vérifiaient donc la clause WHERE
-- des vues, jamais les politiques. On pouvait supprimer une politique entière
-- sans qu'un seul test ne bronche.
--
-- Le fichier des simulacres l'annonçait honnêtement, et c'était la principale
-- limite du harnais : la partie du produit où une erreur ne se voit pas à
-- l'exécution mais expose des données entre concurrents était aussi la seule
-- qui n'était pas couverte.
--
-- Avec ces droits, un test peut écrire `SET LOCAL ROLE authenticated` et
-- éprouver les politiques pour de vrai, localement, sans projet Supabase.
--
-- ── CE QUI RESTE HORS DE PORTÉE ─────────────────────────────────────────────
--
-- Le hook d'émission de jeton, la diffusion Realtime et l'exécution de pg_cron.
-- Ceux-là exigent toujours un vrai projet. Mais les politiques, elles, sont
-- désormais testables ici.
--
-- ── CE FICHIER NE VA JAMAIS EN PRODUCTION ───────────────────────────────────
--
-- Il vit dans `supabase/tests/`, hors du dossier des migrations, et n'est
-- appliqué que par le harnais sur une base jetable. Supabase pose ces droits
-- lui-même sur un vrai projet.

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Les droits de TABLE sont larges, et c'est fidèle à Supabase : c'est RLS qui
-- restreint, pas les GRANT. Un rôle a le droit d'interroger la table ; les
-- politiques décident des lignes qu'il en rapporte. Restreindre ici donnerait
-- un faux vert, en refusant pour la mauvaise raison ce que les politiques
-- doivent refuser pour la bonne.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- `anon` ne lit rien de lui-même. Son seul point d'entrée est la fonction de
-- dépôt de demande d'accès, qui porte son propre GRANT dans la migration.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

-- Les vues créées par les migrations sont couvertes par le GRANT ci-dessus,
-- puisqu'une vue est une relation du schéma. Celles en `security_invoker`
-- appliqueront donc les politiques des tables qu'elles traversent, ce qui est
-- exactement le comportement de production.
