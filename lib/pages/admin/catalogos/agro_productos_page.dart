import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class AgroProductosPage extends StatefulWidget {
  const AgroProductosPage({super.key});

  @override
  State<AgroProductosPage> createState() => _AgroProductosPageState();
}

class _AgroProductosPageState extends State<AgroProductosPage> {
  final _db = FirebaseFirestore.instance;

  final _searchCtrl = TextEditingController();
  String _q = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('productos').withConverter<Map<String, dynamic>>(
            fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
            toFirestore: (m, _) => m,
          );

  Future<void> _openForm({String? docId, Map<String, dynamic>? existing}) async {
    final res = await showDialog<_ProductoFormResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProductoDialog(
        initial: existing,
      ),
    );

    if (res == null) return;

    final now = FieldValue.serverTimestamp();

    if (docId == null) {
      // crear
      await _col.add({
        "nombre": res.nombre.trim(),
        "ingredientesActivos": res.ingredientesActivos.trim(),
        "tipo": res.tipo.trim(),
        "fabricante": res.fabricante.trim(),
        "descripcion": res.descripcion.trim(),
        "createdAt": now,
        "updatedAt": now,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Producto guardado ✅")),
      );
    } else {
      // editar
      await _col.doc(docId).set({
        "nombre": res.nombre.trim(),
        "ingredientesActivos": res.ingredientesActivos.trim(),
        "tipo": res.tipo.trim(),
        "fabricante": res.fabricante.trim(),
        "descripcion": res.descripcion.trim(),
        "updatedAt": now,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Producto actualizado ✅")),
      );
    }
  }

  Future<void> _deleteProducto(String docId, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar producto"),
        content: Text('¿Seguro que quieres eliminar "$nombre"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _col.doc(docId).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Producto eliminado 🗑️")),
    );
  }

  bool _matchesQuery(Map<String, dynamic> data) {
    if (_q.trim().isEmpty) return true;
    final query = _q.trim().toLowerCase();

    final nombre = (data["nombre"] ?? "").toString().toLowerCase();
    final tipo = (data["tipo"] ?? "").toString().toLowerCase();
    final fabricante = (data["fabricante"] ?? "").toString().toLowerCase();

    return nombre.contains(query) || tipo.contains(query) || fabricante.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Agro productos"),
        backgroundColor: AppTheme.pepperRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: "Agregar producto",
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text("Nuevo"),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: "Buscar por nombre, tipo o fabricante…",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: "Limpiar",
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _q = "");
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const Divider(height: 1),

          // List
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _col.orderBy("updatedAt", descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text("Error: ${snap.error}"),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs
                    .where((d) => _matchesQuery(d.data()))
                    .toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text("Aún no hay productos. Presiona “Nuevo”."),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final data = doc.data();

                    final nombre = (data["nombre"] ?? "—").toString();
                    final tipo = (data["tipo"] ?? "—").toString();
                    final fabricante = (data["fabricante"] ?? "—").toString();
                    final ing = (data["ingredientesActivos"] ?? "—").toString();
                    final desc = (data["descripcion"] ?? "").toString();

                    return _ProductoCard(
                      nombre: nombre,
                      tipo: tipo,
                      fabricante: fabricante,
                      ingredientes: ing,
                      descripcion: desc,
                      onEdit: () => _openForm(docId: doc.id, existing: data),
                      onDelete: () => _deleteProducto(doc.id, nombre),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ========================= UI: CARD =========================

class _ProductoCard extends StatelessWidget {
  final String nombre;
  final String tipo;
  final String fabricante;
  final String ingredientes;
  final String descripcion;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductoCard({
    required this.nombre,
    required this.tipo,
    required this.fabricante,
    required this.ingredientes,
    required this.descripcion,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Icon(Icons.science_outlined, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _Chip(text: tipo, icon: Icons.category_outlined),
                            _Chip(text: fabricante, icon: Icons.factory_outlined),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: "Opciones",
                    onSelected: (v) {
                      if (v == "edit") onEdit();
                      if (v == "del") onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: "edit", child: Text("Editar")),
                      PopupMenuItem(value: "del", child: Text("Eliminar")),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _InfoRow(label: "Ingredientes activos", value: ingredientes),
              if (descripcion.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoRow(label: "Descripción", value: descripcion),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black.withValues(alpha: 0.60)),
          const SizedBox(width: 6),
          Text(
            text.isEmpty ? "—" : text,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? "—" : value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ========================= DIALOG: CREATE/EDIT =========================

class _ProductoDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _ProductoDialog({this.initial});

  @override
  State<_ProductoDialog> createState() => _ProductoDialogState();
}

class _ProductoDialogState extends State<_ProductoDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _ingCtrl;
  late final TextEditingController _tipoCtrl;
  late final TextEditingController _fabCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial ?? {};
    _nombreCtrl = TextEditingController(text: (i["nombre"] ?? "").toString());
    _ingCtrl = TextEditingController(text: (i["ingredientesActivos"] ?? "").toString());
    _tipoCtrl = TextEditingController(text: (i["tipo"] ?? "").toString());
    _fabCtrl = TextEditingController(text: (i["fabricante"] ?? "").toString());
    _descCtrl = TextEditingController(text: (i["descripcion"] ?? "").toString());
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ingCtrl.dispose();
    _tipoCtrl.dispose();
    _fabCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _ProductoFormResult(
        nombre: _nombreCtrl.text,
        ingredientesActivos: _ingCtrl.text,
        tipo: _tipoCtrl.text,
        fabricante: _fabCtrl.text,
        descripcion: _descCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    return AlertDialog(
      title: Text(isEdit ? "Editar producto" : "Nuevo producto"),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: "Nombre",
                    hintText: "Ej: Imidacloprid 350",
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Nombre obligatorio" : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ingCtrl,
                  decoration: const InputDecoration(
                    labelText: "Ingredientes activos",
                    hintText: "Ej: Imidacloprid 35% + ...",
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _tipoCtrl,
                  decoration: const InputDecoration(
                    labelText: "Tipo",
                    hintText: "Ej: Insecticida / Fungicida / Fertilizante ...",
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _fabCtrl,
                  decoration: const InputDecoration(
                    labelText: "Fabricante",
                    hintText: "Ej: Bayer",
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Descripción general",
                    hintText: "Notas importantes del producto...",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.pepperRed, foregroundColor: Colors.white),
          onPressed: _submit,
          child: const Text("Guardar"),
        ),
      ],
    );
  }
}

class _ProductoFormResult {
  final String nombre;
  final String ingredientesActivos;
  final String tipo;
  final String fabricante;
  final String descripcion;

  const _ProductoFormResult({
    required this.nombre,
    required this.ingredientesActivos,
    required this.tipo,
    required this.fabricante,
    required this.descripcion,
  });
}
