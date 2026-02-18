import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../models/agro_application.dart';
import '../../../utils/formatters.dart';
import 'application_form_page.dart';

class ApplicationDetailPage extends StatelessWidget {
  final String applicationId;
  const ApplicationDetailPage({super.key, required this.applicationId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection("applications").doc(applicationId);

    return Scaffold(
      appBar: AppBar(title: const Text("Detalle aplicación")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text("No existe el registro."));
          final doc = snap.data!;
          final a = AgroApplication.fromDoc(doc);
          final data = doc.data() as Map<String, dynamic>;
          final focusDesc = data["focusDesc"]?.toString();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _header(a),
              const SizedBox(height: 12),
              _kv("Producto", a.productNameSnapshot),
              _kv("Fecha/Hora", Fmt.dt(a.datetime)),
              _kv("Tipo", a.applicationType),
              _kv("Dosis", a.doseValue == null ? "—" : "${a.doseValue} ${a.doseUnit ?? ""}"),
              _kv("Alcance", a.scope.name),
              if (a.scope == ApplicationScope.focus) ...[
                _kv("Descripción foco", (focusDesc == null || focusDesc.isEmpty) ? "—" : focusDesc),
                _kv("Celdas (temporal)", a.cells.isEmpty ? "—" : a.cells.take(40).join(", ")),
                if (a.cells.length > 40) const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text("… (se muestran 40)", style: TextStyle(fontSize: 12)),
                ),
              ],
              _kv("Estado", a.status.name),
              _kv("Creado", "${a.createdBy} • ${Fmt.dt(a.createdAt)}"),
              if (a.updatedAt != null) _kv("Modificado", "${a.updatedBy} • ${Fmt.dt(a.updatedAt!)}"),
              const SizedBox(height: 16),
              _actions(context, ref, a),
            ],
          );
        },
      ),
    );
  }

  Widget _header(AgroApplication a) {
    return Card(
      child: ListTile(
        title: Text(a.productNameSnapshot, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${Fmt.dt(a.datetime)} • ${a.applicationType}"),
        trailing: Chip(label: Text(a.status.name)),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, DocumentReference ref, AgroApplication a) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ApplicationFormPage(
                        greenhouseId: a.greenhouseId,
                        editId: a.id,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text("Editar"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (a.status == ApplicationStatus.annulled)
                    ? null
                    : () async {
                        final reason = await _reasonDialog(context, title: "Motivo de anulación");
                        if (reason == null) return;
                        await ref.update({
                          "status": ApplicationStatus.annulled.name,
                          "annulledAt": Timestamp.fromDate(DateTime.now()),
                          "annulledBy": uid,
                          "annulReason": reason,
                        });
                      },
                icon: const Icon(Icons.block),
                label: const Text("Anular"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: (a.status == ApplicationStatus.approved || a.status == ApplicationStatus.annulled)
              ? null
              : () async {
                  await ref.update({
                    "status": ApplicationStatus.approved.name,
                    "approvedAt": Timestamp.fromDate(DateTime.now()),
                    "approvedBy": uid,
                  });
                },
          icon: const Icon(Icons.verified),
          label: const Text("Aprobar"),
        ),
      ],
    );
  }

  Future<String?> _reasonDialog(BuildContext context, {required String title}) async {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: "Escribe el motivo…",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? "Sin motivo" : ctrl.text.trim()),
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }
}
