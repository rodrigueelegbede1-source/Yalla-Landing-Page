import 'package:flutter/material.dart';

import 'format.dart';
import 'supabase.dart';
import 'widgets.dart';

class RetoursRecusTab extends StatefulWidget {
  const RetoursRecusTab({super.key, required this.cle, required this.fabricant});

  final int cle;
  final bool fabricant;

  @override
  State<RetoursRecusTab> createState() => _RetoursRecusTabState();
}

class _RetoursRecusTabState extends State<RetoursRecusTab> {
  late Future<List<Map<String, dynamic>>> _retours;

  @override
  void initState() {
    super.initState();
    _retours = _charger();
  }

  @override
  void didUpdateWidget(RetoursRecusTab ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cle != widget.cle) _rafraichir();
  }

  Future<List<Map<String, dynamic>>> _charger() async {
    final rows = await supabase
        .from('v_retours_terrain_recus')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _rafraichir() async {
    final future = _charger();
    if (mounted) setState(() => _retours = future);
    await future;
  }

  String _sujet(BuildContext context, String sujet) {
    final arabe = Localizations.localeOf(context).languageCode == 'ar';
    if (!arabe) {
      return switch (sujet) {
        'qualite' => 'Qualité',
        'prix' => 'Prix',
        'disponibilite' => 'Disponibilité',
        'livraison' => 'Livraison',
        'publicite' => 'Publicité',
        _ => 'Autre',
      };
    }
    return switch (sujet) {
      'qualite' => 'الجودة',
      'prix' => 'السعر',
      'disponibilite' => 'التوفر',
      'livraison' => 'التوصيل',
      'publicite' => 'الإعلان',
      _ => 'أخرى',
    };
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
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
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _retours,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EtatVide(
              icone: Icons.cloud_off_outlined,
              titre: arabe ? 'تعذّر تحميل الملاحظات' : 'Retours indisponibles',
              message: messageErreur(context, snap.error!),
            );
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return EtatVide(
              icone: Icons.forum_outlined,
              titre: arabe ? 'لا توجد ملاحظات ميدانية' : 'Aucun retour terrain',
              message: arabe ? 'ستظهر هنا ملاحظات المتاجر المرتبطة بنطاقك.' : 'Les observations des boutiques de votre périmètre apparaîtront ici.',
            );
          }
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            children: [
              TitreSection(
                arabe ? 'ملاحظات المتاجر' : 'Retours des boutiques',
                detail: widget.fabricant
                    ? (arabe ? 'علامتك فقط' : 'Votre marque uniquement')
                    : (arabe ? 'متاجرك فقط' : 'Votre réseau uniquement'),
              ),
              ...rows.map((row) => Card(
                    margin: const EdgeInsetsDirectional.only(bottom: 9),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 19),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row['point_de_vente'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${row['commune'] ?? ''} · ${_sujet(context, row['sujet'] as String? ?? '')}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(_date(row['created_at']), style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                          if (row['produit'] != null) ...[
                            const SizedBox(height: 10),
                            Text('${arabe ? 'المنتج' : 'Produit'} · ${row['produit']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: 7),
                          Text(row['message'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.45)),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}