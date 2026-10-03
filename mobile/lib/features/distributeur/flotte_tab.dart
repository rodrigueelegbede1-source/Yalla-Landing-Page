import 'package:flutter/material.dart';

import '../../core/comptes.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// La flotte du distributeur : ses livreurs, leur état, et l'ajout d'un livreur.
///
/// CE QUI MANQUAIT. Le distributeur pouvait affecter une course à un livreur,
/// mais n'avait aucun moyen d'en avoir un : les comptes se créaient à la main en
/// SQL, puis par un appel à l'API d'administration. L'écran « Affecter »
/// s'ouvrait donc sur une liste vide, et la seule action du rôle était morte.
///
/// L'ajout passe par [ServiceComptes], donc par la fonction Edge, parce que
/// créer un compte de connexion exige une clé qui ne peut pas vivre dans un APK.
/// Le contrôle reste en SQL : un distributeur ne crée qu'un livreur, et
/// uniquement dans sa propre flotte, quoi que cet écran envoie.
class FlotteTab extends StatefulWidget {
  const FlotteTab({super.key, required this.cle});

  final int cle;

  @override
  State<FlotteTab> createState() => _FlotteTabState();
}

class _FlotteTabState extends State<FlotteTab> {
  late Future<List<Map<String, dynamic>>> _flotte;

  @override
  void initState() {
    super.initState();
    _flotte = _charger();
  }

  @override
  void didUpdateWidget(FlotteTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_ma_flotte')
        .select()
        .order('actif', ascending: false)
        .order('en_ligne', ascending: false)
        .order('nom');
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _flotte = f);
    await f;
  }

  Future<void> _ajouter() async {
    final compte = await showModalBottomSheet<CompteCree>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormulaireLivreur(),
    );
    if (compte == null) return;
    if (!mounted) return;

    await _rafraichir();
    if (!mounted) return;
    await afficherIdentifiants(context, compte, role: 'livreur');
  }

  Future<void> _basculerActif(Map<String, dynamic> livreur) async {
    final actif = livreur['actif'] == true;
    final nom = livreur['nom'] as String? ?? 'Ce livreur';

    if (actif) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Écarter $nom ?'),
          content: const Text(
            'Il ne recevra plus de course et n\'apparaîtra plus sur votre carte. '
            'Son historique de livraisons est conservé, et vous pouvez le '
            'réintégrer à tout moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Écarter'),
            ),
          ],
        ),
      );
      if (confirme != true) return;
    }

    try {
      await supabase.rpc('ecarter_livreur', params: {
        'p_livreur_id': livreur['livreur_id'],
        'p_actif': !actif,
      });
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messageErreur(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouter,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter un livreur'),
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _flotte,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EtatVide(
                icone: Icons.cloud_off_outlined,
                titre: 'Chargement impossible',
                message: messageErreur(context, snap.error!),
              );
            }

            final flotte = snap.data ?? const [];
            if (flotte.isEmpty) {
              return EtatVide(
                icone: Icons.two_wheeler_outlined,
                titre: 'Aucun livreur',
                message: 'Sans livreur, vous voyez les ruptures mais ne pouvez '
                    'les affecter à personne. Ajoutez votre premier livreur : '
                    'vous lui remettrez son numéro et son mot de passe en main propre.',
                action: 'Ajouter un livreur',
                onAction: _ajouter,
              );
            }

            final actifs = flotte.where((l) => l['actif'] == true).toList();
            final ecartes = flotte.where((l) => l['actif'] != true).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                TitreSection('Ma flotte',
                    detail: '${actifs.where((l) => l['en_ligne'] == true).length} '
                        'en ligne sur ${actifs.length}'),
                ...actifs.map((l) => _Livreur(livreur: l, onBasculer: () => _basculerActif(l))),
                if (ecartes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TitreSection('Écartés', detail: '${ecartes.length}'),
                  ...ecartes.map((l) => _Livreur(livreur: l, onBasculer: () => _basculerActif(l))),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Livreur extends StatelessWidget {
  const _Livreur({required this.livreur, required this.onBasculer});

  final Map<String, dynamic> livreur;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context) {
    final actif = livreur['actif'] == true;
    final enLigne = livreur['en_ligne'] == true;
    final enCours = (livreur['courses_en_cours'] as num?)?.toInt() ?? 0;
    final terminees = (livreur['livraisons_terminees'] as num?)?.toInt() ?? 0;
    final majLe = DateTime.tryParse(livreur['position_maj_le']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: !actif
                  ? Colors.grey.shade300
                  : enLigne
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
              child: Icon(
                Icons.two_wheeler,
                color: !actif ? Colors.grey : (enLigne ? Colors.green : Colors.orange),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(livreur['nom'] as String? ?? 'Livreur',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(livreur['telephone'] as String? ?? '',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!actif)
                        const Etiquette(texte: 'ÉCARTÉ', couleur: Colors.grey)
                      else if (enLigne)
                        Etiquette(
                          // Une position vieille de plus de cinq minutes veut
                          // dire que le téléphone ne remonte plus rien : à
                          // distinguer d'un livreur réellement suivi.
                          texte: majLe != null &&
                                  DateTime.now().difference(majLe).inMinutes < 5
                              ? 'EN LIGNE'
                              : 'EN LIGNE, POSITION FIGÉE',
                          couleur: majLe != null &&
                                  DateTime.now().difference(majLe).inMinutes < 5
                              ? Colors.green
                              : Colors.orange,
                        )
                      else
                        const Etiquette(texte: 'HORS LIGNE', couleur: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(
                        enCours > 0 ? '$enCours en cours · $terminees livrées' : '$terminees livrées',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: actif ? 'Écarter de la flotte' : 'Réintégrer',
              icon: Icon(actif ? Icons.person_remove_outlined : Icons.person_add_alt_1),
              onPressed: onBasculer,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le formulaire d'ajout. Trois champs, pas un de plus : sur le terrain, un
/// formulaire long ne se remplit pas.
class _FormulaireLivreur extends StatefulWidget {
  const _FormulaireLivreur();

  @override
  State<_FormulaireLivreur> createState() => _FormulaireLivreurState();
}

class _FormulaireLivreurState extends State<_FormulaireLivreur> {
  final _cleForm = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  late String _motDePasse = ServiceComptes.motDePasseLisible();

  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!(_cleForm.currentState?.validate() ?? false)) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      final compte = await const ServiceComptes().creer(
        nom: _nom.text,
        telephone: _telephone.text,
        role: 'livreur',
        motDePasse: _motDePasse,
      );
      if (!mounted) return;
      Navigator.pop(context, compte);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = messageCompte(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _cleForm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nouveau livreur',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Son numéro lui servira d\'identifiant. Vous lui remettrez le mot '
              'de passe en main propre.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du livreur',
                hintText: 'Koffi Yao',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Nom trop court' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                hintText: '07 06 30 30 30',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  telephoneSaisiValide(v) ? null : 'Numéro incomplet',
            ),
            const SizedBox(height: 12),
            _ChampMotDePasse(
              valeur: _motDePasse,
              onRegenerer: () =>
                  setState(() => _motDePasse = ServiceComptes.motDePasseLisible()),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _envoi ? null : _valider,
              child: _envoi
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Créer le compte'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Le mot de passe, affiché en clair et régénérable.
///
/// Le masquer serait absurde : il est dicté au livreur dans la minute qui suit,
/// et c'est la personne qui le crée qui doit pouvoir le lire.
class _ChampMotDePasse extends StatelessWidget {
  const _ChampMotDePasse({required this.valeur, required this.onRegenerer});

  final String valeur;
  final VoidCallback onRegenerer;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: 'Mot de passe à remettre',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'En générer un autre',
            icon: const Icon(Icons.refresh),
            onPressed: onRegenerer,
          ),
        ),
        child: Text(
          valeur,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3),
        ),
      );
}

/// Contrôle de saisie partagé par les formulaires de création.
bool telephoneSaisiValide(String? saisie) {
  final chiffres = (saisie ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return chiffres.length >= 10;
}

/// Montre les identifiants une fois le compte créé.
///
/// C'est le seul moment où le mot de passe est lisible : il n'est stocké nulle
/// part en clair, et personne, pas même l'administrateur, ne pourra le retrouver.
/// L'écran doit donc être explicite, et ne pas se fermer tout seul.
Future<void> afficherIdentifiants(
  BuildContext context,
  CompteCree compte, {
  required String role,
}) {
  // OÙ CE COMPTE SE CONNECTE, ET POURQUOI IL FAUT LE DIRE. Le paramètre `role`
  // était reçu et jamais lu. Or les trois rôles ne se connectent pas au même
  // endroit : la boutique et le livreur dans cette application, le distributeur
  // sur le site. Sans cette phrase, l'agent qui vient d'inscrire un grossiste
  // lui dit d'installer l'application, où il ne trouvera rien, et l'erreur ne
  // se découvre qu'au moment où il essaie.
  final surLeSite = role == 'distributeur' || role == 'fabricant';

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.check_circle_outline, size: 40),
      title: const Text('Compte créé'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notez ces identifiants et remettez-les maintenant. Le mot de passe '
            'ne pourra plus être affiché.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          _Ligne(label: 'Identifiant', valeur: compte.telephone),
          const SizedBox(height: 8),
          _Ligne(label: 'Mot de passe', valeur: compte.motDePasse),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(surLeSite ? Icons.language : Icons.phone_android,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    surLeSite
                        ? 'Il se connecte sur yalla.ci, depuis un ordinateur ou '
                            'un téléphone. Son espace n’est pas dans cette '
                            'application.'
                        : 'Il se connecte dans cette application, avec ces '
                            'mêmes identifiants.',
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('C\'est noté'),
        ),
      ],
    ),
  );
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.label, required this.valeur});
  final String label;
  final String valeur;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          SelectableText(valeur,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2)),
        ],
      );
}
