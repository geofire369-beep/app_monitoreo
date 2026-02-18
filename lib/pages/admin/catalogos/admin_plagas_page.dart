import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

class AdminPlagasPage extends StatefulWidget {
  const AdminPlagasPage({super.key});

  @override
  State<AdminPlagasPage> createState() => _AdminPlagasPageState();
}

class _AdminPlagasPageState extends State<AdminPlagasPage> {
  final _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('plagas');

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Plagas'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Agregar',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
        onPressed: () => _openEditor(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _col.orderBy('nombre').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

            if (docs.isEmpty) {
              return _Empty(
                title: 'Sin registros',
                subtitle: 'Aún no hay plagas/enfermedades en el catálogo.',
                accent: accent,
              );
            }

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data();

                final nombre = (data['nombre'] ?? '').toString().trim();
                final tipo = (data['tipo'] ?? 'PLAGA').toString().trim().toUpperCase();
                final nivelesAny = data['niveles'];
                final niveles = (nivelesAny is List)
                    ? nivelesAny.map((e) => e.toString()).where((x) => x.trim().isNotEmpty).toList()
                    : <String>[];

                return _PlagaCard(
                  accent: accent,
                  nombre: nombre.isEmpty ? '(Sin nombre)' : nombre,
                  tipo: tipo,
                  niveles: niveles,
                  onEdit: () => _openEditor(context, docId: d.id, initial: data),
                  onDelete: () => _confirmDelete(context, docId: d.id, nombre: nombre),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, {required String docId, required String nombre}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Eliminar'),
          content: Text('¿Seguro que quieres eliminar "${nombre.isEmpty ? "este registro" : nombre}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _col.doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eliminado')));
    }
  }

  Future<void> _openEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? initial,
  }) async {
    final res = await showModalBottomSheet<_PlagaPayload?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlagaEditorSheet(
        accent: AppTheme.pepperRed,
        initial: initial,
      ),
    );

    if (res == null) return;

    final payload = <String, dynamic>{
      'nombre': res.nombre.trim(),
      'tipo': res.tipo.trim().toUpperCase(),
      'niveles': res.niveles.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    };

    if (docId == null) {
      await _col.add(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado')));
    } else {
      await _col.doc(docId).set(payload, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualizado')));
    }
  }
}

// ===================== UI Widgets =====================

class _PlagaCard extends StatelessWidget {
  final Color accent;
  final String nombre;
  final String tipo;
  final List<String> niveles;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlagaCard({
    required this.accent,
    required this.nombre,
    required this.tipo,
    required this.niveles,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEnf = tipo == 'ENFERMEDAD';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(isEnf ? Icons.healing_outlined : Icons.bug_report_outlined, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(text: isEnf ? 'Enfermedad' : 'Plaga'),
                    if (niveles.isNotEmpty) _Pill(text: 'Niveles: ${niveles.join(", ")}'),
                    if (niveles.isEmpty)
                      Text('Sin niveles', style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;

  const _Empty({required this.title, required this.subtitle, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.list_alt_outlined, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(color: Colors.black.withValues(alpha: 0.70))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Editor BottomSheet =====================

class _PlagaPayload {
  final String nombre;
  final String tipo; // PLAGA | ENFERMEDAD
  final List<String> niveles;

  _PlagaPayload({required this.nombre, required this.tipo, required this.niveles});
}

class _PlagaEditorSheet extends StatefulWidget {
  final Color accent;
  final Map<String, dynamic>? initial;

  const _PlagaEditorSheet({
    required this.accent,
    this.initial,
  });

  @override
  State<_PlagaEditorSheet> createState() => _PlagaEditorSheetState();
}

class _PlagaEditorSheetState extends State<_PlagaEditorSheet> {
  late final TextEditingController _nombre;
  late final TextEditingController _nivelCtrl;

  String _tipo = 'PLAGA';
  final List<String> _niveles = [];

  @override
  void initState() {
    super.initState();

    final init = widget.initial ?? const <String, dynamic>{};

    _nombre = TextEditingController(text: (init['nombre'] ?? '').toString());
    _nivelCtrl = TextEditingController();

    _tipo = (init['tipo'] ?? 'PLAGA').toString().trim().toUpperCase();
    if (_tipo != 'PLAGA' && _tipo != 'ENFERMEDAD') _tipo = 'PLAGA';

    final nAny = init['niveles'];
    if (nAny is List) {
      _niveles.addAll(nAny.map((e) => e.toString()).map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _nivelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: EdgeInsets.fromLTRB(14, 14, 14, 14 + bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 22, offset: const Offset(0, 14)),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.edit_outlined, color: widget.accent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Registrar / Editar',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la plaga/enfermedad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: _tipo,
                  items: const [
                    DropdownMenuItem(value: 'PLAGA', child: Text('Plaga')),
                    DropdownMenuItem(value: 'ENFERMEDAD', child: Text('Enfermedad')),
                  ],
                  onChanged: (v) => setState(() => _tipo = v ?? 'PLAGA'),
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 12),
                const Text('Niveles', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nivelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Agregar nivel (ej. Bajo, Medio, Alto)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addNivel(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addNivel,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _niveles.isEmpty
                      ? [
                          Text('Sin niveles', style: TextStyle(color: Colors.black.withValues(alpha: 0.60))),
                        ]
                      : _niveles.map((n) {
                          return InputChip(
                            label: Text(n),
                            onDeleted: () => setState(() => _niveles.remove(n)),
                          );
                        }).toList(),
                ),

                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _save,
                        child: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addNivel() {
    final v = _nivelCtrl.text.trim();
    if (v.isEmpty) return;

    final exists = _niveles.any((e) => e.toLowerCase() == v.toLowerCase());
    if (!exists) {
      setState(() => _niveles.add(v));
    }
    _nivelCtrl.clear();
  }

  void _save() {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pon un nombre.')));
      return;
    }

    Navigator.pop(
      context,
      _PlagaPayload(nombre: nombre, tipo: _tipo, niveles: List<String>.from(_niveles)),
    );
  }
}
