import 'package:flutter/material.dart';

import '../../core/comptes.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';

/// L'agent recenseur inscrit un distributeur, sur le terrain.
///
/// ── POURQUOI CET ÉCRAN MANQUAIT, ET CE QUE ÇA COÛTAIT ──────────────────────
///
/// La base l'autorise depuis la migration de gestion du réseau :
/// `creer_compte_metier` accepte qu'un agent crée un point de vente OU un
/// distributeur. Seul l'écran n'existait pas.
///
/// L'écart entre ce que la base permet et ce que l'application propose n'est
/// pas théorique. Un agent qui recense une commune y rencontre les grossistes
/// avant les boutiques : ce sont eux qui savent quelles échoppes existent. Ne
/// pas pouvoir les inscrire sur place obligeait à les renvoyer vers le
/// formulaire du site, puis à attendre une validation, c'est-à-dire à perdre la
/// personne qu'on avait en face de soi.
///
/// ── AFFILIÉ OU INDÉPENDANT, ET POURQUOI LA QUESTION SE POSE ICI ────────────
///
/// Un distributeur rattaché à une marque ne portera que celle-là. Un
/// indépendant portera ce qu'on lui attribuera ensuite. Ce n'est pas un détail
/// administratif : le rattachement décide de ce qu'il verra dès sa première
/// connexion, et se corriger plus tard demande l'administrateur. Autant poser
/// la question à l'agent, qui a le grossiste devant lui.
///
/// ── PAS DE POSITION, CONTRAIREMENT À UNE BOUTIQUE ──────────────────────────
///
/// Une boutique est un point sur une carte : c'est sa position qui décide quel
/// livreur est le plus proche. Un distributeur est une organisation, dont le
/// périmètre se définit par les boutiques qu'il dessert, pas par un point GPS.
/// Lui demander de relever une position donnerait une donnée fausse et
/// inutilisée.
class InscriptionDistributeur extends StatefulWidget {
  const InscriptionDistributeur({super.key});

  @override
  State<InscriptionDistributeur> createState() => _InscriptionDistributeurState();
}

class _InscriptionDistributeurState extends State<InscriptionDistributeur> {
  final _cleForm = GlobalKey<FormState>();
  final _nomGerant = TextEditingController();
  final _nomSociete = TextEditingController();
  final _telephone = TextEditingController();

  late String _motDePasse = ServiceComptes.motDePasseLisible();

  List<Map<String, dynamic>> _marques = const [];
  String? _marqueChoisie;
  bool _chargementMarques = true;

  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _chargerMarques();
  }

  @override
  void dispose() {
    _nomGerant.dispose();
    _nomSociete.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _chargerMarques() async {
    try {
      final lignes = await supabase
          .from('fabricants')
          .select('id, nom')
          .eq('statut', 'actif')
          .order('nom');
      if (!mounted) return;
      setState(() {
        _marques = List<Map<String, dynamic>>.from(lignes);
        _chargementMarques = false;
      });
    } catch (_) {
      // Sans la liste, le distributeur se crée indépendant. C'est rattrapable
      // par l'administrateur, alors qu'un agent bloqué devant un grossiste ne
      // l'est pas.
      if (mounted) setState(() => _chargementMarques = false);
    }
  }

  Future<void> _valider() async {
    if (!(_cleForm.currentState?.validate() ?? false)) return;

    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      final compte = await const ServiceComptes().creer(
        // Le compte appartient au gérant, pas à la société : c'est lui qui se
        // connectera. Même règle que pour une boutique.
        nom: _nomGerant.text,
        telephone: _telephone.text,
        role: 'distributeur',
        motDePasse: _motDePasse,
        details: {
          'nom_societe': _nomSociete.text.trim(),
          if (_marqueChoisie != null) 'fabricant_id': _marqueChoisie,
        },
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
    return Scaffold(
      backgroundColor: Jetons.creme,
      appBar: AppBar(
        backgroundColor: Jetons.vert800,
        title: const Text('Inscrire un distributeur'),
      ),
      body: Form(
        key: _cleForm,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Jetons.vert700.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(Jetons.rChamp),
              ),
              child: const Text(
                'Un distributeur ne voit aucune boutique tant qu’on ne lui en '
                'attribue pas. Prévenez-le : c’est l’administrateur qui lui '
                'donne sa première, et il pourra déclarer les suivantes lui-même.',
                style: TextStyle(fontSize: 13.5, height: 1.45),
              ),
            ),
            const SizedBox(height: 22),

            TextFormField(
              controller: _nomSociete,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de la société',
                hintText: 'Distrib Yamoussoukro',
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Indiquez le nom de la société'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nomGerant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du gérant',
                hintText: 'Celui qui se connectera',
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Indiquez le nom du gérant'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              // Un numéro se lit de gauche à droite même en arabe : sans cette
              // direction imposée, le RTL inverse l'ordre des groupes.
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'Téléphone du gérant',
                hintText: '07 06 30 30 30',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Indiquez son numéro'
                  : null,
            ),
            const SizedBox(height: 22),

            const Text('Marque portée',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_chargementMarques)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Indépendant'),
                    selected: _marqueChoisie == null,
                    onSelected: (_) => setState(() => _marqueChoisie = null),
                  ),
                  for (final m in _marques)
                    ChoiceChip(
                      label: Text(m['nom'] as String? ?? ''),
                      selected: _marqueChoisie == m['id'],
                      onSelected: (_) =>
                          setState(() => _marqueChoisie = m['id'] as String?),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              _marqueChoisie == null
                  ? 'Il portera les marques qu’on lui attribuera. C’est le cas '
                      'le plus fréquent sur le terrain.'
                  : 'Il ne portera que cette marque. Ce rattachement ne se '
                      'corrige qu’auprès de l’administrateur.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Jetons.encre.withValues(alpha: .58)),
            ),
            const SizedBox(height: 22),

            // Le mot de passe est montré AVANT l'envoi, pas après. L'agent le
            // dicte au gérant pendant qu'il remplit le formulaire, et vérifie
            // qu'il l'a bien noté avant de valider. Le découvrir après coup
            // oblige à le redemander, dans la rue, à quelqu'un qui range déjà
            // son téléphone.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Jetons.blanc,
                borderRadius: BorderRadius.circular(Jetons.rCarte),
                boxShadow: Jetons.ombreCarte,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MOT DE PASSE À DICTER',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: .08,
                                fontWeight: FontWeight.w600,
                                color: Jetons.encre.withValues(alpha: .55))),
                        const SizedBox(height: 6),
                        Text(_motDePasse,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: Jetons.vert800)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'En générer un autre',
                    onPressed: () => setState(
                        () => _motDePasse = ServiceComptes.motDePasseLisible()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),

            if (_erreur != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Jetons.alerte.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(Jetons.rChamp),
                  border: Border.all(color: Jetons.alerte.withValues(alpha: .34)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 20, color: Jetons.alerte),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_erreur!,
                            style: const TextStyle(fontSize: 14, height: 1.4))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 26),
            SizedBox(
              // La pleine largeur vient du parent, jamais du thème : un
              // `Size.fromHeight` dans le thème pose une largeur minimale
              // infinie, ce qui a déjà écrasé une liste entière ailleurs.
              width: double.infinity,
              child: FilledButton(
                onPressed: _envoi ? null : _valider,
                child: _envoi
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Jetons.blanc))
                    : const Text('Créer le compte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
