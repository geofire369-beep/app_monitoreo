import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportsHistoryPage extends StatelessWidget {
  const ReportsHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection("reports")
        .orderBy("createdAt", descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text("Historial de reportes")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Sin reportes guardados."));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = docs[i].data();
              final ghName = (m["greenhouseName"] ?? m["greenhouseId"] ?? "").toString();

              final fromTs = m["from"];
              final toTs = m["to"];
              final createdTs = m["createdAt"];

              final from = (fromTs is Timestamp) ? fromTs.toDate() : null;
              final to = (toTs is Timestamp) ? toTs.toDate() : null;
              final createdAt = (createdTs is Timestamp) ? createdTs.toDate() : null;

              return ListTile(
                title: Text(ghName),
                subtitle: Text(
                  "Periodo: ${from?.toString().split(' ').first ?? '—'} → ${to?.toString().split(' ').first ?? '—'}",
                ),
                trailing: Text(createdAt?.toString().split('.').first ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}
