import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class RetoursTab extends StatefulWidget {
  const RetoursTab({super.key, required this.cle, required this.onChangement});

  final int cle;
  final VoidCallback onChangement;

  @override
  State<RetoursTab> createState() => _RetoursTabState();
}

class _RetoursTabState extends State<RetoursTab> {
  static const _sujets = <String, String>{
    'qualite': 'Qualité du produit',
    'prix': 'Prix',
    'disponibilite': 'Disponibilité',
    'livraison': 'Livraison',
    'publicite': 'Publicité reçue',
    'autre': 'Autre retour terrain',
  };

  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  String? _cible;
  String? _produit;
  String _sujet = 'qualite';
  bool _envoi = false;
  late Future<_DonneesRetours> _donnees;

  @override
  void initState() {
    super.initState();
    _donnees = _charger();
  }

  @override
  void didUpdateWidget(RetoursTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<_DonneesRetours> _charger() async {
    final reponses = await Future.wait<Object?>([
      supabase.from('v_destinataires_retours').select().order('destinataire_nom'),
      supabase.from('v_catalogue_point_de_vente').select('produit_id, produit_nom, fabricant_id, fabricant_nom').order('produit_nom'),
      supabase.from('v_produits_retour_distributeur').select().order('produit_nom'),
      supabase.from('v_mes_retours_terrain').select().order('created_at', ascending: false).limit(30),
    ]);
    return _DonneesRetours(
      destinataires: List<Map<String, dynamic>>.from(reponses[0] as List),
      produits: List<Map<String, dynamic>>.from(reponses[1] as List),
      produitsDistributeur: List<Map<String, dynamic>>.from(reponses[2] as List),
      historiques: List<Map<String, dynamic>>.from(reponses[3] as List),
    );
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _donnees = future);
    await future;
  }

  Future<void> _envoyer(String? cible) async {
    if (!_formKey.currentState!.validate() || cible == null || _envoi) return;
    final elements = cible.split(':');
    if (elements.length != 2) return;
    final role = elements.first;
    final destinataireId = elements.last;
    final l = Localizations.localeOf(context).languageCode;

    setState(() => _envoi = true);
    try {
      await supabase.rpc('envoyer_retour_terrain', params: {
        'p_destinataire_role': role,
        'p_destinataire_id': destinataireId,
        'p_produit_id': _produit,
        'p_sujet': _sujet,
        'p_message': _message.text.trim(),
      });
      if (!mounted) return;
      _message.clear();
      widget.onChangement();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l == 'ar' ? 'تم إرسال ملاحظتك إلى الجهة المعنية.' : 'Votre retour a été transmis au destinataire.')));
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messageErreur(context, e))));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  String _sujetAffiche(BuildContext context, String sujet) {
    if (Localizations.localeOf(context).languageCode != 'ar') return _sujets[sujet] ?? _sujets['autre']!;
    return switch (sujet) {
      'qualite' => 'جودة المنتج',
      'prix' => 'السعر',
      'disponibilite' => 'التوفر',
      'livraison' => 'التوصيل',
      'publicite' => 'إعلان مستلَم',
      _ => 'ملاحظة ميدانية أخرى',
    };
  }

  String _date(dynamic valeur) {
    final date = DateTime.tryParse('$valeur')?.toLocal();
    if (date == null) return '';
    final jour = date.day.toString().padLeft(2, '0');
    final mois = date.month.toString().padLeft(2, '0');
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$jour/$mois · $heure:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final arabe = Localizations.localeOf(context).languageCode == 'ar';
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: FutureBuilder<_DonneesRetours>(
        future: _donnees,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(icone: Icons.cloud_off_outlined, titre: arabe ? 'تعذّر تحميل الملاحظات' : 'Retours indisponibles', message: messageErreur(context, snap.error!));
          }
          final donnees = snap.data!;
          final cibles = donnees.destinataires;
          final cleParDefaut = cibles.isEmpty ? null : '${cibles.first['destinataire_role']}:${cibles.first['destinataire_id']}';
          final cibleActive = cibles.any((c) => '${c['destinataire_role']}:${c['destinataire_id']}' == _cible) ? _cible : cleParDefaut;
          final elementsCible = cibleActive?.split(':') ?? const <String>[];
          final roleActif = elementsCible.isEmpty ? null : elementsCible.first;
          final idActif = elementsCible.length < 2 ? null : elementsCible.last;
            final produitsAutorises = roleActif == 'distributeur'
              ? donnees.produitsDistributeur.where((p) => p['distributeur_id'] == idActif).toList()
              : donnees.produits.where((p) => roleActif != 'fabricant' || p['fabricant_id'] == idActif).toList();
          final produitActif = produitsAutorises.any((p) => p['produit_id'] == _produit) ? _produit : null;

          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            children: [
              TitreSection(arabe ? 'أرسل ملاحظة ميدانية' : 'Faire remonter un retour'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(arabe ? 'ستُرسل الملاحظة إلى العلامة أو الموزّع المرتبط بمتجرك.' : 'Votre retour est adressé à une marque ou au distributeur de votre boutique.', style: const TextStyle(fontSize: 13, height: 1.4)),
                        if (cibles.isEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            arabe
                                ? 'لم تُربط أي علامة أو موزّع بمتجرك بعد. تواصل مع المسؤول عن شبكتك.'
                                : 'Aucun fabricant ou distributeur n’est encore attribué à votre boutique. Contactez l’administrateur du réseau.',
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: cibleActive,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: arabe ? 'إلى' : 'Destinataire'),
                          items: cibles.map((c) {
                            final role = c['destinataire_role'] as String? ?? '';
                            final nom = c['destinataire_nom'] as String? ?? '';
                            return DropdownMenuItem(value: '$role:${c['destinataire_id']}', child: Text('${role == 'fabricant' ? (arabe ? 'علامة' : 'Fabricant') : (arabe ? 'موزّع' : 'Distributeur')} · $nom', maxLines: 1, overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: cibles.isEmpty ? null : (value) => setState(() { _cible = value; _produit = null; }),
                          validator: (value) => value == null ? (arabe ? 'لا يوجد مستلم مرتبط بمتجرك' : 'Aucun destinataire associé à votre boutique') : null,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: produitActif,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: arabe ? 'المنتج (اختياري للموزّع)' : 'Produit (facultatif pour le distributeur)'),
                          items: produitsAutorises.map((p) => DropdownMenuItem(value: p['produit_id'] as String, child: Text(p['produit_nom'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: produitsAutorises.isEmpty ? null : (value) => setState(() => _produit = value),
                          validator: (value) => roleActif == 'fabricant' && value == null ? (arabe ? 'اختر منتجًا من علامة المستلم' : 'Choisissez un produit de ce fabricant') : null,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _sujet,
                          decoration: InputDecoration(labelText: arabe ? 'الموضوع' : 'Sujet'),
                          items: _sujets.keys.map((sujet) => DropdownMenuItem(value: sujet, child: Text(_sujetAffiche(context, sujet)))).toList(),
                          onChanged: (value) => setState(() => _sujet = value ?? 'autre'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _message,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 1200,
                          decoration: InputDecoration(labelText: arabe ? 'وصف الملاحظة' : 'Votre observation', hintText: arabe ? 'اشرح ما لاحظته في الميدان.' : 'Décrivez ce que vous observez sur le terrain.'),
                          validator: (value) => (value?.trim().length ?? 0) < 5 ? (arabe ? 'اكتب خمس حروف على الأقل' : 'Écrivez au moins 5 caractères') : null,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: cibles.isEmpty || _envoi ? null : () => _envoyer(cibleActive),
                          icon: _envoi ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
                          label: Text(arabe ? 'إرسال الملاحظة' : 'Envoyer le retour'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              TitreSection(arabe ? 'ملاحظاتي السابقة' : 'Mes retours précédents', detail: '${donnees.historiques.length}'),
              if (donnees.historiques.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(arabe ? 'ستظهر ملاحظاتك هنا بعد إرسالها.' : 'Vos retours transmis apparaîtront ici.')))
              else
                ...donnees.historiques.map((retour) => Card(
                      margin: const EdgeInsetsDirectional.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.chat_bubble_outline, color: Jetons.vert700),
                        title: Text(retour['destinataire'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_sujetAffiche(context, retour['sujet'] as String? ?? '')}${retour['produit'] == null ? '' : ' · ${retour['produit']}'}\n${retour['message'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
                        trailing: Text(_date(retour['created_at']), style: const TextStyle(fontSize: 10)),
                        isThreeLine: true,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _DonneesRetours {
  const _DonneesRetours({
    required this.destinataires,
    required this.produits,
    required this.produitsDistributeur,
    required this.historiques,
  });

  final List<Map<String, dynamic>> destinataires;
  final List<Map<String, dynamic>> produits;
  final List<Map<String, dynamic>> produitsDistributeur;
  final List<Map<String, dynamic>> historiques;
}