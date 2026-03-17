import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../mapas/mapa_page.dart';
import '../../models/mapa_model.dart';

class AdminMapasPage extends StatelessWidget {
  const AdminMapasPage({super.key});

  static const _col = 'greenhouses_maps';

  // (Ya no se usa porque quitamos eliminar desde esta vista,
  // pero lo dejo por si luego lo reactivas)
  Future<bool> _confirmDelete(BuildContext context, String mapName) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar mapa'),
        content: Text(
          '¿Seguro que deseas eliminar "$mapName"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );

    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapas de invernadero'),
        backgroundColor: AppTheme.pepperRed,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.pepperGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Crear mapa'),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MapaPage()),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection(_col).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          // Convertir a modelo para mostrar info fácil
          final maps = <GreenhouseMap>[];
          for (final d in docs) {
            try {
              maps.add(GreenhouseMap.fromDoc(d.id, d.data()));
            } catch (_) {
              // si hay algún doc mal, lo ignoramos para no romper la lista
            }
          }

          // Ordenar por updatedAt (ISO string) si existe
          maps.sort((a, b) {
            final aRaw =
                (docs.firstWhere((x) => x.id == a.id).data()['updatedAt'] ?? '')
                    .toString();
            final bRaw =
                (docs.firstWhere((x) => x.id == b.id).data()['updatedAt'] ?? '')
                    .toString();
            final aDt =
                DateTime.tryParse(aRaw) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDt =
                DateTime.tryParse(bRaw) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDt.compareTo(aDt);
          });

          if (maps.isEmpty) {
            return const Center(
              child: Text('Aún no hay mapas. Presiona "Crear mapa".'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: maps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final m = maps[i];

              return Card(
                child: ListTile(
                  title: Text(
                    m.name.isEmpty ? '(sin nombre)' : m.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Capillas: ${m.capillas.length}  ·  Postes N:${m.postsNorth} S:${m.postsSouth}  ·  Líneas: ${m.firstLineNo}..${m.lastLineNo}',
                  ),
                  onTap: () async {
                    // ✅ Solo entrar a edición
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MapaPage(mapId: m.id)),
                    );
                  },

                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
