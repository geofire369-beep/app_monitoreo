import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/agro_application.dart';
import '../../../utils/formatters.dart';
import 'application_form_page.dart';
import 'application_detail_page.dart';

class AgroApplicationsPage extends StatefulWidget {
  const AgroApplicationsPage({super.key});

  @override
  State<AgroApplicationsPage> createState() => _AgroApplicationsPageState();
}

class _AgroApplicationsPageState extends State<AgroApplicationsPage> {
  String? _greenhouseId;
  ApplicationStatus? _status;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Agroquímicos - Aplicaciones"),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020, 1, 1),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _filters(),
          const Divider(height: 1),
          Expanded(child: _list()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_greenhouseId == null)
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ApplicationFormPage(
                      greenhouseId: _greenhouseId!,
                    ),
                  ),
                );
              },
        icon: const Icon(Icons.add),
        label: const Text("Nueva"),
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _greenhousePicker()),
              const SizedBox(width: 12),
              Expanded(child: _statusPicker()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text("Rango: ${Fmt.dt(_range.start)}  →  ${Fmt.dt(_range.end)}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _greenhousePicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("greenhouses").orderBy("name").snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const LinearProgressIndicator();
        }
        final docs = snap.data!.docs;
        return DropdownButtonFormField<String>(
          value: _greenhouseId,
          decoration: const InputDecoration(
            labelText: "Invernadero",
            border: OutlineInputBorder(),
          ),
          items: docs.map((d) {
            final name = (d.data() as Map<String, dynamic>)["name"]?.toString() ?? d.id;
            return DropdownMenuItem(value: d.id, child: Text(name));
          }).toList(),
          onChanged: (v) => setState(() => _greenhouseId = v),
        );
      },
    );
  }

  Widget _statusPicker() {
    return DropdownButtonFormField<ApplicationStatus?>(
      value: _status,
      decoration: const InputDecoration(
        labelText: "Estado",
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text("Todos")),
        DropdownMenuItem(value: ApplicationStatus.draft, child: Text("Borrador")),
        DropdownMenuItem(value: ApplicationStatus.registered, child: Text("Registrado")),
        DropdownMenuItem(value: ApplicationStatus.approved, child: Text("Aprobado")),
        DropdownMenuItem(value: ApplicationStatus.annulled, child: Text("Anulado")),
      ],
      onChanged: (v) => setState(() => _status = v),
    );
  }

  Widget _list() {
    if (_greenhouseId == null) {
      return const Center(child: Text("Selecciona un invernadero."));
    }

    Query q = FirebaseFirestore.instance
        .collection("applications")
        .where("greenhouseId", isEqualTo: _greenhouseId)
        .where("datetime", isGreaterThanOrEqualTo: Timestamp.fromDate(_range.start))
        .where("datetime", isLessThanOrEqualTo: Timestamp.fromDate(_range.end))
        .orderBy("datetime", descending: true);

    if (_status != null) {
      q = q.where("status", isEqualTo: _status!.name);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Sin registros en el rango seleccionado."));

        final apps = docs.map((d) => AgroApplication.fromDoc(d)).toList();

        return ListView.separated(
          itemCount: apps.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = apps[i];
            return ListTile(
              title: Text(a.productNameSnapshot),
              subtitle: Text("${Fmt.dt(a.datetime)} • ${a.applicationType} • ${a.scope.name}"),
              trailing: _statusChip(a.status),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ApplicationDetailPage(applicationId: a.id)),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _statusChip(ApplicationStatus s) {
    String label;
    switch (s) {
      case ApplicationStatus.draft:
        label = "Borrador";
        break;
      case ApplicationStatus.registered:
        label = "Registrado";
        break;
      case ApplicationStatus.approved:
        label = "Aprobado";
        break;
      case ApplicationStatus.annulled:
        label = "Anulado";
        break;
    }
    return Chip(label: Text(label));
  }
}
