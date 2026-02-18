import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../models/agro_application.dart';

class ApplicationFormPage extends StatefulWidget {
  final String greenhouseId;
  final String? editId;

  const ApplicationFormPage({
    super.key,
    required this.greenhouseId,
    this.editId,
  });

  @override
  State<ApplicationFormPage> createState() => _ApplicationFormPageState();
}

class _ApplicationFormPageState extends State<ApplicationFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  ApplicationScope _scope = ApplicationScope.general;
  ApplicationStatus _status = ApplicationStatus.registered;

  String? _productId;
  String _productSnapshot = "";

  String _applicationType = "aspersión";
  double? _doseValue;
  String _doseUnit = "ml/L";

  String? _targetPestId;
  DateTime _dt = DateTime.now();

  String? _notes;

  // Temporal hasta mapa: celdas o descripción de foco
  final _focusCellsCtrl = TextEditingController(); // "r10c5,r10c6,..."
  final _focusDescCtrl = TextEditingController();  // "Cama 3, sección B..."

  @override
  void initState() {
    super.initState();
    _initIfEdit();
  }

  Future<void> _initIfEdit() async {
    if (widget.editId == null) {
      setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance.collection("applications").doc(widget.editId).get();
    if (!doc.exists) {
      setState(() => _loading = false);
      return;
    }
    final a = AgroApplication.fromDoc(doc);
    _scope = a.scope;
    _status = a.status;
    _productId = a.productId;
    _productSnapshot = a.productNameSnapshot;
    _applicationType = a.applicationType;
    _doseValue = a.doseValue;
    _doseUnit = a.doseUnit ?? "ml/L";
    _targetPestId = a.targetPestId;
    _dt = a.datetime;
    _notes = a.notes;

    // Esto es para tu versión GRID. Si aún no guardas cells, dejar vacío.
    if (a.cells.isNotEmpty) {
      _focusCellsCtrl.text = a.cells.join(",");
    }
    // Si decides guardar descripción (recomendado):
    // _focusDescCtrl.text = (doc.data() as Map<String,dynamic>)["focusDesc"]?.toString() ?? "";

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _focusCellsCtrl.dispose();
    _focusDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? "Editar aplicación" : "Nueva aplicación")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _scopeCard(),
                      const SizedBox(height: 12),
                      _productPicker(),
                      const SizedBox(height: 12),
                      _typeDoseRow(),
                      const SizedBox(height: 12),
                      _datetimePicker(),
                      const SizedBox(height: 12),
                      _pestPicker(),
                      const SizedBox(height: 12),
                      _statusPicker(),
                      const SizedBox(height: 12),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: "Observaciones",
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _notes,
                        maxLines: 3,
                        onChanged: (v) => _notes = v,
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(isEdit ? "Guardar cambios" : "Guardar"),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  Container(
                    color: Colors.black.withOpacity(0.25),
                    child: const Center(child: CircularProgressIndicator()),
                  )
              ],
            ),
    );
  }

  Widget _scopeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Alcance", style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<ApplicationScope>(
              value: ApplicationScope.general,
              groupValue: _scope,
              title: const Text("Aplicación general (todo el invernadero)"),
              onChanged: (v) => setState(() => _scope = v!),
            ),
            RadioListTile<ApplicationScope>(
              value: ApplicationScope.focus,
              groupValue: _scope,
              title: const Text("Foco / Área específica"),
              onChanged: (v) => setState(() => _scope = v!),
            ),
            if (_scope == ApplicationScope.focus) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _focusDescCtrl,
                decoration: const InputDecoration(
                  labelText: "Descripción del foco (temporal)",
                  border: OutlineInputBorder(),
                  hintText: "Ej: Cama 3, Sección B, lado norte",
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _focusCellsCtrl,
                decoration: const InputDecoration(
                  labelText: "Celdas (opcional, temporal)",
                  border: OutlineInputBorder(),
                  hintText: "r10c5,r10c6,r10c7",
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _productPicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("products").orderBy("nameCommercial").snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs;
        return DropdownButtonFormField<String>(
          value: _productId,
          decoration: const InputDecoration(
            labelText: "Producto aplicado",
            border: OutlineInputBorder(),
          ),
          items: docs.map((d) {
            final name = (d.data() as Map<String, dynamic>)["nameCommercial"]?.toString() ?? d.id;
            return DropdownMenuItem(value: d.id, child: Text(name));
          }).toList(),
          validator: (v) => (v == null || v.isEmpty) ? "Selecciona un producto" : null,
          onChanged: (v) {
            if (v == null) return;
            final d = docs.firstWhere((x) => x.id == v);
            final name = (d.data() as Map<String, dynamic>)["nameCommercial"]?.toString() ?? v;
            setState(() {
              _productId = v;
              _productSnapshot = name;
            });
          },
        );
      },
    );
  }

  Widget _typeDoseRow() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: _applicationType,
            decoration: const InputDecoration(
              labelText: "Tipo",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: "aspersión", child: Text("aspersión")),
              DropdownMenuItem(value: "nebulización", child: Text("nebulización")),
              DropdownMenuItem(value: "drench", child: Text("drench")),
            ],
            onChanged: (v) => setState(() => _applicationType = v ?? "aspersión"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            initialValue: _doseValue?.toString(),
            decoration: const InputDecoration(
              labelText: "Dosis",
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => _doseValue = double.tryParse(v),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _doseUnit,
            decoration: const InputDecoration(
              labelText: "Unidad",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: "ml/L", child: Text("ml/L")),
              DropdownMenuItem(value: "g/L", child: Text("g/L")),
              DropdownMenuItem(value: "ml/ha", child: Text("ml/ha")),
            ],
            onChanged: (v) => setState(() => _doseUnit = v ?? "ml/L"),
          ),
        ),
      ],
    );
  }

  Widget _datetimePicker() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text("Fecha y hora"),
      subtitle: Text(_dt.toString()),
      trailing: const Icon(Icons.edit_calendar),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          firstDate: DateTime(2020, 1, 1),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: _dt,
        );
        if (d == null) return;
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dt));
        if (t == null) return;
        setState(() => _dt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
      },
    );
  }

  Widget _pestPicker() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("pests").orderBy("name").snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        return DropdownButtonFormField<String>(
          value: _targetPestId,
          decoration: const InputDecoration(
            labelText: "Objetivo (opcional)",
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text("—")),
            ...docs.map((d) {
              final name = (d.data() as Map<String, dynamic>)["name"]?.toString() ?? d.id;
              return DropdownMenuItem(value: d.id, child: Text(name));
            }),
          ],
          onChanged: (v) => setState(() => _targetPestId = v),
        );
      },
    );
  }

  Widget _statusPicker() {
    return DropdownButtonFormField<ApplicationStatus>(
      value: _status,
      decoration: const InputDecoration(
        labelText: "Estado",
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: ApplicationStatus.draft, child: Text("Borrador")),
        DropdownMenuItem(value: ApplicationStatus.registered, child: Text("Registrado")),
        DropdownMenuItem(value: ApplicationStatus.approved, child: Text("Aprobado")),
        DropdownMenuItem(value: ApplicationStatus.annulled, child: Text("Anulado")),
      ],
      onChanged: (v) => setState(() => _status = v ?? ApplicationStatus.registered),
    );
  }

  List<String> _parseCells(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return [];
    return cleaned
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();
      final id = widget.editId ?? const Uuid().v4();

      final app = AgroApplication(
        id: id,
        greenhouseId: widget.greenhouseId,
        scope: _scope,
        cells: _scope == ApplicationScope.focus ? _parseCells(_focusCellsCtrl.text) : const [],
        productId: _productId!,
        productNameSnapshot: _productSnapshot,
        datetime: _dt,
        applicationType: _applicationType,
        doseValue: _doseValue,
        doseUnit: _doseUnit,
        targetPestId: _targetPestId,
        responsibleUserId: uid,
        status: _status,
        notes: _notes,
        createdAt: now,
        createdBy: uid,
        updatedAt: widget.editId != null ? now : null,
        updatedBy: widget.editId != null ? uid : null,
        changeReason: widget.editId != null ? "Edición desde UI" : null,
        approvedAt: null,
        approvedBy: null,
        annulledAt: null,
        annulledBy: null,
        annulReason: null,
        attachments: const [],
      );

      final ref = FirebaseFirestore.instance.collection("applications").doc(id);

      // si estás editando, preserva createdAt/createdBy originales
      if (widget.editId != null) {
        final old = await ref.get();
        if (old.exists) {
          final oldData = old.data() as Map<String, dynamic>;
          await ref.set({
            ...app.toMap(),
            "createdAt": oldData["createdAt"],
            "createdBy": oldData["createdBy"],
            // guardamos la descripción temporal del foco:
            "focusDesc": _focusDescCtrl.text.trim(),
          }, SetOptions(merge: false));
        } else {
          await ref.set({...app.toMap(), "focusDesc": _focusDescCtrl.text.trim()});
        }
      } else {
        await ref.set({...app.toMap(), "focusDesc": _focusDescCtrl.text.trim()});
      }

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
