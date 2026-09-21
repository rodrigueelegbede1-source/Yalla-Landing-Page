// Fonction Edge `creer-compte`
//
// Crée un compte Yalla complet : le compte de connexion dans `auth.users`, la
// ligne `utilisateurs`, et la ligne du rôle (boutique, distributeur, livreur).
//
// POURQUOI ELLE EXISTE. Créer un utilisateur dans `auth.users` exige la clé
// `service_role`, qui contourne toutes les politiques RLS. Cette clé ne peut
// donc jamais entrer dans un APK : un fichier décompilé et c'est la base entière
// qui est lisible. Tant qu'elle n'existait pas, les comptes se créaient à la
// main, en SQL, ce qui rendait le recensement de terrain impossible.
//
// LE DÉCOUPAGE DES DROITS, qui est le point important :
//
//   * `service_role` sert UNIQUEMENT à créer et, en cas d'échec, à supprimer le
//     compte de connexion. Elle ne touche à aucune table métier.
//   * la ligne métier est créée par `creer_compte_metier`, appelée avec le
//     JETON DE L'APPELANT. `auth_role()` rend donc le rôle réel de l'agent ou
//     du distributeur, et le contrôle de périmètre s'applique pour de bon.
//
// Autrement dit, même avec cette fonction déployée, un distributeur ne peut
// créer qu'un livreur de sa propre flotte. Le contrôle vit en SQL, pas ici, et
// ce fichier ne peut pas le contourner.
//
// Déploiement :
//   supabase functions deploy creer-compte

import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_SUPABASE = Deno.env.get('SUPABASE_URL')!;
const CLE_ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const CLE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const ENTETES = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

/// Même normalisation qu'en SQL (`normaliser_telephone`) et qu'en Dart
/// (`lib/core/telephone.dart`). Les trois doivent rendre EXACTEMENT le même
/// résultat, sans quoi un compte se crée sous une adresse et se connecte sous
/// une autre, et rien dans le message d'erreur ne le dit.
///
/// La forme canonique est `2250706303030` : treize chiffres, sans `+`. Une
/// première version de ce fichier préfixait un `+`, ce qui produisait bien la
/// même adresse technique mais enregistrait un numéro différent de celui
/// qu'aurait écrit la base.
function normaliserTelephone(brut: string): string {
  let v = (brut ?? '').replace(/[^0-9]/g, '');
  if (v.startsWith('00225')) v = v.slice(2);
  // Dix chiffres = numéro national, quel que soit le premier. Les mobiles
  // commencent par 01, 05 ou 07, les fixes par 25 ou 27 : une condition sur le
  // zéro initial refusait tous les fixes.
  if (v.length === 10) v = `225${v}`;
  return v;
}

function emailTechnique(telephone: string): string {
  return `${normaliserTelephone(telephone)}@yalla.ci`;
}

function reponse(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), { status: statut, headers: ENTETES });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: ENTETES });
  if (req.method !== 'POST') return reponse({ erreur: 'Méthode non autorisée' }, 405);

  const autorisation = req.headers.get('Authorization');
  if (!autorisation) return reponse({ erreur: 'Authentification requise' }, 401);

  let charge: Record<string, unknown>;
  try {
    charge = await req.json();
  } catch {
    return reponse({ erreur: 'Requête illisible' }, 400);
  }

  const nom = String(charge.nom ?? '').trim();
  const role = String(charge.role ?? '').trim();
  const motDePasse = String(charge.mot_de_passe ?? '');
  const details = (charge.details ?? {}) as Record<string, unknown>;
  // Facultatif : la demande d'accès que cette création vient satisfaire.
  const demandeId = charge.demande_id ? String(charge.demande_id) : null;
  const telephone = normaliserTelephone(String(charge.telephone ?? ''));

  if (!nom) return reponse({ erreur: 'Le nom est obligatoire' }, 400);
  // Treize chiffres exactement : `225` puis les dix du numéro ivoirien.
  if (telephone.length !== 13 || !telephone.startsWith('225')) {
    return reponse({ erreur: 'Numéro de téléphone invalide. Exemple : 07 06 30 30 30' }, 400);
  }
  // Huit caractères : ce mot de passe est dicté au gérant sur le pas de sa
  // porte, pas tapé dans un gestionnaire. Plus long serait retapé de travers.
  if (motDePasse.length < 8) {
    return reponse({ erreur: 'Le mot de passe doit faire au moins 8 caractères' }, 400);
  }

  const admin = createClient(URL_SUPABASE, CLE_SERVICE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Le client qui portera le jeton de l'appelant. C'est lui qui fera l'écriture
  // métier, donc c'est son rôle qui sera vérifié.
  const appelant = createClient(URL_SUPABASE, CLE_ANON, {
    global: { headers: { Authorization: autorisation } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: utilisateurAppelant, error: erreurJeton } = await appelant.auth.getUser();
  if (erreurJeton || !utilisateurAppelant?.user) {
    return reponse({ erreur: 'Session expirée, reconnectez-vous' }, 401);
  }

  // 1. Le compte de connexion.
  const { data: cree, error: erreurCreation } = await admin.auth.admin.createUser({
    email: emailTechnique(telephone),
    password: motDePasse,
    email_confirm: true,
    user_metadata: { nom, telephone },
  });

  if (erreurCreation || !cree?.user) {
    const message = erreurCreation?.message ?? 'Création du compte impossible';
    const dejaPris = /already|registered|exist/i.test(message);
    return reponse(
      { erreur: dejaPris ? 'Ce numéro est déjà rattaché à un compte Yalla' : message },
      dejaPris ? 409 : 400,
    );
  }

  // 2. La ligne métier, sous l'identité de l'appelant.
  const { data: metier, error: erreurMetier } = await appelant.rpc('creer_compte_metier', {
    p_auth_user_id: cree.user.id,
    p_nom: nom,
    p_telephone: telephone,
    p_role: role,
    p_details: details,
  });

  // 3. Rien à moitié fait. Un compte de connexion sans ligne métier produirait
  //    un utilisateur qui se connecte et n'a accès à rien, sans aucun moyen de
  //    s'en rendre compte depuis l'application.
  if (erreurMetier) {
    await admin.auth.admin.deleteUser(cree.user.id);
    const refus = /insufficient_privilege|ne permet pas/i.test(erreurMetier.message ?? '');
    return reponse({ erreur: erreurMetier.message }, refus ? 403 : 400);
  }

  // 4. La demande d'accès est marquée validée, dans le même geste.
  //
  //    L'ORDRE COMPTE : le compte d'abord, la demande ensuite. Si l'on marquait
  //    la demande en premier et que la création échouait, l'administrateur
  //    verrait une demande traitée sans compte derrière, et personne ne le
  //    rattraperait. Dans l'autre sens, l'incident laisse un compte valide et
  //    une demande encore en attente : visible, et corrigeable en un clic.
  let demandeTraitee = true;
  if (demandeId) {
    const { error: erreurDemande } = await appelant.rpc('marquer_demande_validee', {
      p_demande_id: demandeId,
      p_utilisateur_id: (metier as Record<string, unknown>).utilisateur_id,
    });
    if (erreurDemande) demandeTraitee = false;
  }

  return reponse({
    ...(metier as Record<string, unknown>),
    auth_user_id: cree.user.id,
    identifiant: telephone,
    demande_traitee: demandeTraitee,
  }, 201);
});
