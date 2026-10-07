import 'package:flutter/material.dart';

import 'supabase.dart';

class VisuelCommunication extends StatefulWidget {
  const VisuelCommunication({
    super.key,
    required this.url,
    required this.bucket,
    this.hauteur = 180,
    this.ajustement = BoxFit.cover,
  });

  final String? url;
  final String? bucket;
  final double hauteur;
  final BoxFit ajustement;

  @override
  State<VisuelCommunication> createState() => _VisuelCommunicationState();
}

class _VisuelCommunicationState extends State<VisuelCommunication> {
  late Future<String?> _urlResolue;

  @override
  void initState() {
    super.initState();
    _urlResolue = _resoudre();
  }

  @override
  void didUpdateWidget(VisuelCommunication ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.url != widget.url || ancien.bucket != widget.bucket) {
      _urlResolue = _resoudre();
    }
  }

  Future<String?> _resoudre() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('https://')) return url;
    final bucket = widget.bucket;
    if (bucket == null || bucket.isEmpty) return null;
    return supabase.storage.from(bucket).createSignedUrl(url, 3600);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _urlResolue,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SizedBox(
              height: widget.hauteur,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          final url = snap.data;
          if (url == null || url.isEmpty) return const SizedBox.shrink();
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: double.infinity,
              height: widget.hauteur,
              fit: widget.ajustement,
              errorBuilder: (_, __, ___) => SizedBox(
                height: widget.hauteur,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          );
        },
      );
}
