import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'format.dart';
import 'supabase.dart';
import 'visuel_communication.dart';
import 'widgets.dart';
import '../l10n/app_localizations.dart';

class CommunicationsSoumissionTab extends StatelessWidget {
  const CommunicationsSoumissionTab({super.key, this.onTermine});

  final VoidCallback? onTermine;

  @override
  Widget build(BuildContext context) => _EspaceCommunications(
        admin: false,
        onTermine: onTermine,
      );
}

class CommunicationsAdministrateurTab extends StatelessWidget {
  const CommunicationsAdministrateurTab({super.key});

  @override
  Widget build(BuildContext context) =>
      const _EspaceCommunications(admin: true);
}

class _EspaceCommunications extends StatefulWidget {
  const _EspaceCommunications({required this.admin, this.onTermine});

  final bool admin;
  final VoidCallback? onTermine;

  @override
  State<_EspaceCommunications> createState() => _EspaceCommunicationsState();
}

class _EspaceCommunicationsState extends State<_EspaceCommunications> {
  int _vue = 0;
  int _cle = 0;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    if (!widget.admin) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0, label: Text(l.communicationMesSoumissions)),
                ButtonSegment(value: 1, label: Text(l.nouvelleCommunication)),
              ],
              selected: {_vue},
              onSelectionChanged: (selection) =>
                  setState(() => _vue = selection.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _vue,
              children: [
                _MesSoumissions(cle: _cle),
                _FormulaireCommunication(
                  admin: false,
                  onTermine: () {
                    setState(() => _cle++);
                    widget.onTermine?.call();
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(l.communicationAValider)),
              ButtonSegment(value: 1, label: Text(l.nouvelleCommunication)),
            ],
            selected: {_vue},
            onSelectionChanged: (selection) =>
                setState(() => _vue = selection.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _vue,
            children: [
              _FileApprobation(cle: _cle),
              _FormulaireCommunication(
                admin: true,
                onTermine: () {
                  setState(() => _cle++);
                  widget.onTermine?.call();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileApprobation extends StatefulWidget {
  const _FileApprobation({required this.cle});

  final int cle;

  @override
  State<_FileApprobation> createState() => _FileApprobationState();
}

class _FileApprobationState extends State<_FileApprobation> {
  late Future<List<Map<String, dynamic>>> _communications;

  @override
  void initState() {
    super.initState();
    _communications = _charger();
  }

  @override
  void didUpdateWidget(_FileApprobation ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes =
        await supabase.from('v_diffusions_a_valider').select().order('cree_le');
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _communications = future);
    await future;
  }

  Future<void> _traiter(Map<String, dynamic> communication,
      {required bool approuver}) async {
    final l = L.of(context);
    String? motif;
    if (!approuver) {
      motif = await showDialog<String>(
        context: context,
        builder: (context) => _MotifRefus(),
      );
      if (motif == null) return;
    }

    try {
      final accepte = await supabase.rpc(
        approuver ? 'valider_communication' : 'refuser_communication',
        params: {
          'p_diffusion_id': communication['diffusion_id'],
          if (!approuver) 'p_motif': motif,
        },
      );
      if (accepte != true) throw StateError(l.communicationDejaTraitee);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                approuver ? l.communicationPubliee : l.communicationRefusee)),
      );
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageErreur(context, e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _communications,
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
          final lignes = snap.data ?? const [];
          if (lignes.isEmpty) {
            return EtatVide(
              icone: Icons.verified_outlined,
              titre: l.aucuneCommunicationAValider,
              message: l.aucuneCommunicationAValiderMessage,
            );
          }
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
            children: [
              TitreSection(l.communicationAValider, detail: '${lignes.length}'),
              ...lignes.map((ligne) => _CarteCommunication(
                    ligne: ligne,
                    actions: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _traiter(ligne, approuver: false),
                            icon: const Icon(Icons.close),
                            label: Text(l.refuser),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _traiter(ligne, approuver: true),
                            icon: const Icon(Icons.check),
                            label: Text(l.approuverPublier),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _MesSoumissions extends StatefulWidget {
  const _MesSoumissions({required this.cle});

  final int cle;

  @override
  State<_MesSoumissions> createState() => _MesSoumissionsState();
}

class _MesSoumissionsState extends State<_MesSoumissions> {
  late Future<List<Map<String, dynamic>>> _communications;

  @override
  void initState() {
    super.initState();
    _communications = _charger();
  }

  @override
  void didUpdateWidget(_MesSoumissions ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final lignes = await supabase
        .from('v_mes_communications')
        .select()
        .order('cree_le', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(lignes);
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _communications = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _communications,
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
          final lignes = snap.data ?? const [];
          if (lignes.isEmpty) {
            return EtatVide(
              icone: Icons.campaign_outlined,
              titre: l.aucuneSoumissionTitre,
              message: l.aucuneSoumissionMessage,
            );
          }
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
            children: [
              TitreSection(l.communicationMesSoumissions,
                  detail: '${lignes.length}'),
              ...lignes.map((ligne) {
                final statut = ligne['statut_validation'] as String?;
                return _CarteCommunication(
                  ligne: ligne,
                  actions: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Chip(
                      avatar: Icon(_iconeStatut(statut)),
                      label: Text(_libelleStatut(l, statut)),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  IconData _iconeStatut(String? statut) => switch (statut) {
        'publiee' => Icons.check_circle_outline,
        'refusee' => Icons.cancel_outlined,
        _ => Icons.schedule,
      };

  String _libelleStatut(L l, String? statut) => switch (statut) {
        'publiee' => l.communicationStatutPubliee,
        'refusee' => l.communicationStatutRefusee,
        _ => l.communicationEnAttente,
      };
}

class _FormulaireCommunication extends StatefulWidget {
  const _FormulaireCommunication({required this.admin, this.onTermine});

  final bool admin;
  final VoidCallback? onTermine;

  @override
  State<_FormulaireCommunication> createState() =>
      _FormulaireCommunicationState();
}

class _FormulaireCommunicationState extends State<_FormulaireCommunication> {
  final _titre = TextEditingController();
  final _message = TextEditingController();
  String _type = 'notification';
  String? _nomVisuel;
  Uint8List? _visuel;
  bool _occupe = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _choisirVisuel() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (resultat == null || !mounted) return;
    final fichier = resultat.files.single;
    if (fichier.bytes == null ||
        fichier.bytes!.isEmpty ||
        fichier.bytes!.length > 5 * 1024 * 1024) {
      setState(() => _erreur = L.of(context).visuelLimite);
      return;
    }
    setState(() {
      _nomVisuel = fichier.name;
      _visuel = fichier.bytes;
      _erreur = null;
    });
  }

  Future<void> _envoyer() async {
    final l = L.of(context);
    if (_titre.text.trim().length < 3 || _message.text.trim().length < 3) {
      setState(() => _erreur = l.communicationChampsObligatoires);
      return;
    }
    if (_type == 'splash_publicitaire' && _visuel == null) {
      setState(() => _erreur = l.publiciteImageObligatoire);
      return;
    }
    final utilisateur = supabase.auth.currentUser;
    if (utilisateur == null) {
      setState(() => _erreur = l.erreurSession);
      return;
    }

    setState(() {
      _occupe = true;
      _erreur = null;
    });
    String? cheminVisuel;
    try {
      String? urlVisuel;
      if (_visuel != null) {
        final extension = _nomVisuel!.split('.').last.toLowerCase();
        final mime = switch (extension) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          _ => 'image/webp',
        };
        cheminVisuel =
            '${utilisateur.id}/communications/${DateTime.now().microsecondsSinceEpoch}_${_nomVisuel!.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
        await supabase.storage.from('notifications-brouillons').uploadBinary(
              cheminVisuel,
              _visuel!,
              fileOptions: FileOptions(contentType: mime, upsert: false),
            );
        urlVisuel = cheminVisuel;
      }

      if (widget.admin) {
        await supabase.rpc('diffuser_communication_admin', params: {
          'p_type': _type,
          'p_titre': _titre.text.trim(),
          'p_message': _message.text.trim(),
          'p_visuel_url': urlVisuel,
        });
      } else {
        await supabase.rpc('soumettre_communication', params: {
          'p_type': _type,
          'p_titre': _titre.text.trim(),
          'p_message': _message.text.trim(),
          'p_commune': null,
          'p_visuel_url': urlVisuel,
        });
      }

      if (!mounted) return;
      _titre.clear();
      _message.clear();
      setState(() {
        _type = 'notification';
        _nomVisuel = null;
        _visuel = null;
      });
      widget.onTermine?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.admin
                ? l.communicationPubliee
                : l.communicationSoumise)),
      );
    } catch (e) {
      if (cheminVisuel != null) {
        try {
          await supabase.storage
              .from('notifications-brouillons')
              .remove([cheminVisuel]);
        } catch (_) {}
      }
      if (mounted) setState(() => _erreur = messageErreur(context, e));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final soumission = !widget.admin;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      children: [
        TitreSection(
          soumission ? l.nouvelleCommunication : l.diffusionAdmin,
          detail:
              soumission ? l.approbationAdminRequise : l.diffuseeDirectement,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'notification', label: Text(l.noteInformation)),
            ButtonSegment(
                value: 'splash_publicitaire', label: Text(l.publiciteVisuelle)),
          ],
          selected: {_type},
          onSelectionChanged: _occupe
              ? null
              : (selection) => setState(() => _type = selection.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titre,
          maxLength: 120,
          decoration: InputDecoration(labelText: l.titreCommunication),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _message,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: l.texteCommunication),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _occupe ? null : _choisirVisuel,
          icon: const Icon(Icons.image_outlined),
          label: Text(_nomVisuel ?? l.ajouterVisuel),
        ),
        if (_visuel != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(_visuel!, height: 180, fit: BoxFit.contain),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _occupe
                  ? null
                  : () => setState(() {
                        _nomVisuel = null;
                        _visuel = null;
                      }),
              icon: const Icon(Icons.delete_outline),
              label: Text(l.retirerVisuel),
            ),
          ),
        ],
        if (soumission) ...[
          const SizedBox(height: 8),
          Text(l.communicationPorteeBoutiques,
              style: const TextStyle(fontSize: 12)),
        ],
        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _occupe ? null : _envoyer,
          icon: _occupe
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_outlined),
          label: Text(
              soumission ? l.soumettrePourApprobation : l.diffuserMaintenant),
        ),
      ],
    );
  }
}

class _CarteCommunication extends StatelessWidget {
  const _CarteCommunication({required this.ligne, required this.actions});

  final Map<String, dynamic> ligne;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final estPublicite = ligne['type'] == 'splash_publicitaire';
    final date = DateTime.tryParse(ligne['cree_le']?.toString() ?? '');
    final image = ligne['visuel_url'] as String?;
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(estPublicite
                    ? Icons.campaign_outlined
                    : Icons.info_outline),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(ligne['organisation'] as String? ??
                        ligne['emetteur'] as String? ??
                        '')),
                Text(estPublicite ? l.publiciteVisuelle : l.noteInformation),
              ],
            ),
            const SizedBox(height: 10),
            Text(ligne['titre'] as String? ?? '',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(ligne['message'] as String? ?? '',
                style: const TextStyle(height: 1.4)),
            if (image != null && image.isNotEmpty) ...[
              const SizedBox(height: 10),
              VisuelCommunication(
                url: image,
                bucket: 'notifications-brouillons',
              ),
            ],
            if ((ligne['motif_refus'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                '${l.motifRefus} : ${ligne['motif_refus']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              date == null
                  ? l.communicationEnAttente
                  : l.communicationSoumiseLe(
                      date.toLocal().toString().substring(0, 16)),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 10),
            actions,
          ],
        ),
      ),
    );
  }
}

class _MotifRefus extends StatefulWidget {
  @override
  State<_MotifRefus> createState() => _MotifRefusState();
}

class _MotifRefusState extends State<_MotifRefus> {
  final _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Text(l.refuserCommunication),
      content: TextField(
        controller: _motif,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: l.motifRefus),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.annuler)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_motif.text.trim()),
          child: Text(l.refuser),
        ),
      ],
    );
  }
}
