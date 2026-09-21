import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

/// Les messages que le réseau adresse au boutiquier.
///
/// POURQUOI CET ÉCRAN EXISTE. L'administrateur pouvait émettre une
/// notification, un splash ou un sondage, et personne ne les recevait : la
/// diffusion partait, était stockée, sa portée était comptée, et aucun écran ne
/// l'affichait. Rien ne le signalait, puisque aucune erreur ne se produisait.
/// C'était un aller sans retour, découvert en auditant l'état du produit avant
/// le pilote plutôt que par un utilisateur.
///
/// TROIS NATURES DE MESSAGE, TROIS TRAITEMENTS :
///
///   * une NOTIFICATION se lit et se referme. C'est la consigne de service,
///     la maintenance du samedi, le marché fermé ;
///   * un SPLASH PUBLICITAIRE est la même chose vue du fabricant. Il se
///     distingue visuellement mais ne demande rien ;
///   * un SONDAGE attend une réponse, et c'est le seul qui donne quelque chose
///     en retour au réseau.
///
/// CE QUE CET ÉCRAN NE FAIT PAS, DÉLIBÉRÉMENT : marquer un message comme lu.
/// Rien ne trace la lecture côté base, et le tableau de bord de
/// l'administrateur écrit « non suivi » plutôt qu'un pourcentage inventé. Poser
/// un accusé ici sans la table qui va avec produirait un compteur qui ne
/// compte rien. Le jour où la lecture devra être mesurée, ce sera une table, un
/// appel de plus ici, et une colonne dans la vue de l'administrateur.
///
/// Le non-lu affiché sur l'onglet est donc LOCAL au téléphone : ce que ce
/// téléphone n'a pas encore ouvert. C'est une commodité pour le boutiquier, pas
/// une mesure pour l'exploitant, et les deux ne doivent pas être confondues.
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key, required this.cle, required this.onChangement});

  final int cle;
  final VoidCallback onChangement;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  late Future<List<Map<String, dynamic>>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = _charger();
  }

  @override
  void didUpdateWidget(MessagesTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_mes_diffusions')
        .select()
        .order('date_envoi', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final f = _charger();
    if (mounted) setState(() => _messages = f);
    await f;
  }

  Future<void> _repondre(Map<String, dynamic> message, String optionId) async {
    final l = L.of(context);
    try {
      await supabase.rpc('repondre_sondage', params: {
        'p_notification_id': message['diffusion_id'],
        'p_option_id': optionId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.reponseEnregistree)));
      widget.onChangement();
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
    final l = L.of(context);

    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _messages,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(
              icone: Icons.cloud_off_outlined,
              titre: l.chargementImpossible,
              message: messageErreur(context, snap.error!),
            );
          }

          final messages = snap.data ?? const [];
          if (messages.isEmpty) {
            return EtatVide(
              icone: Icons.mark_email_read_outlined,
              titre: l.messagesVideTitre,
              message: l.messagesVideTexte,
            );
          }

          // Les sondages sans réponse remontent en tête : ce sont les seuls qui
          // attendent quelque chose du boutiquier. Le reste suit par date.
          final ordonnes = [...messages]..sort((a, b) {
              final aAttend = a['type'] == 'sondage' && a['ma_reponse'] == null;
              final bAttend = b['type'] == 'sondage' && b['ma_reponse'] == null;
              if (aAttend != bAttend) return aAttend ? -1 : 1;
              return 0;
            });

          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
            children: [
              TitreSection(l.messagesTitre,
                  detail: l.messagesCompteur(messages.length)),
              ...ordonnes.map((m) => _Message(
                    message: m,
                    onRepondre: (optionId) => _repondre(m, optionId),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onRepondre});

  final Map<String, dynamic> message;
  final void Function(String optionId) onRepondre;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final couleurs = Theme.of(context).colorScheme;

    final type = message['type'] as String? ?? 'notification';
    final sondage = type == 'sondage';
    final splash = type == 'splash_publicitaire';
    final options = (message['options'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final maReponse = message['ma_reponse'] as String?;
    final anciennete = (message['anciennete_secondes'] as num?)?.toInt() ?? 0;

    final icone = sondage
        ? Icons.how_to_vote_outlined
        : splash
            ? Icons.campaign_outlined
            : Icons.info_outline;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      // Un sondage sans réponse se distingue au premier coup d'œil : c'est le
      // seul message qui demande quelque chose, et il doit se voir sans être
      // lu.
      color: sondage && maReponse == null
          ? couleurs.primaryContainer.withValues(alpha: .35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, size: 20, color: couleurs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message['titre'] as String? ?? '',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  duree(anciennete),
                  style: TextStyle(fontSize: 11, color: couleurs.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message['message'] as String? ?? '',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),

            if (sondage && options.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Les réponses sont des boutons pleins, pas une liste à cocher :
              // le boutiquier répond d'un doigt, debout derrière son comptoir,
              // sans valider ensuite.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((o) {
                  final id = o['id'] as String;
                  final choisie = maReponse == id;
                  return choisie
                      ? FilledButton.icon(
                          onPressed: () => onRepondre(id),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(o['libelle'] as String? ?? ''),
                        )
                      : OutlinedButton(
                          onPressed: () => onRepondre(id),
                          child: Text(o['libelle'] as String? ?? ''),
                        );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                maReponse == null ? l.sondageEnAttente : l.sondageModifiable,
                style: TextStyle(fontSize: 11.5, color: couleurs.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
