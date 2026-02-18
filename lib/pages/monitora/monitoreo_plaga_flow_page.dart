import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../models/mapa_model.dart';

class MonitoraPlagaFlowPage extends StatefulWidget {
  const MonitoraPlagaFlowPage({super.key});

  @override
  State<MonitoraPlagaFlowPage> createState() => _MonitoraPlagaFlowPageState();
}

class _MonitoraPlagaFlowPageState extends State<MonitoraPlagaFlowPage> {
  static const _mapsCol = 'greenhouses_maps';

  GreenhouseMap? _selectedMap;
  CapillaDef? _selectedCap;
  int? _selectedCapIndexSorted;

  bool _saving = false;

  void _selectMap(GreenhouseMap m) {
    setState(() {
      _selectedMap = m;
      _selectedCap = null;
      _selectedCapIndexSorted = null;
    });
  }

  void _selectCap(CapillaDef cap, int sortedIndex) {
    setState(() {
      _selectedCap = cap;
      _selectedCapIndexSorted = sortedIndex;
    });
  }

  Future<void> _startMonitoringPlaga({
    required GreenhouseMap map,
    required CapillaDef cap,
    required int capIndexSorted,
    required int lineNo,
  }) async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance.collection('monitoreo').add({
        "type": "plaga",
        "status": "in_progress",
        "createdAt": FieldValue.serverTimestamp(),
        "monitoraUid": uid,
        "greenhouseId": map.id,
        "greenhouseName": map.name,
        "capillaId": cap.id,
        "capillaName": cap.name,
        "capillaIndex": capIndexSorted + 1,
        "capillaStartLineNo": cap.startLineNo,
        "capillaEndLineNo": cap.endLineNo,
        "lineNo": lineNo,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Monitoreo iniciado ✅  Línea $lineNo")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreo de plaga'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(_mapsCol).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;

          final maps = <GreenhouseMap>[];
          for (final d in docs) {
            try {
              maps.add(GreenhouseMap.fromDoc(d.id, d.data()));
            } catch (_) {}
          }

          maps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          // si no hay selección y existe al menos 1 mapa, preselecciona el primero
          if (_selectedMap == null && maps.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _selectMap(maps.first);
            });
          }

          final selectedMap = _selectedMap;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // =========================
                // 1) INVERNADERO
                // =========================
                _SectionTitle(title: "1) Invernadero"),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  value: selectedMap?.id,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: "Selecciona invernadero",
                  ),
                  items: maps
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name.isEmpty ? "(sin nombre)" : m.name),
                          ))
                      .toList(),
                  onChanged: (id) {
                    final m = maps.firstWhere((x) => x.id == id);
                    _selectMap(m);
                  },
                ),

                const SizedBox(height: 14),

                // =========================
                // 2) CAPILLA (ordenada)
                // =========================
                _SectionTitle(title: "2) Capilla"),
                const SizedBox(height: 8),

                if (selectedMap == null)
                  const _HintBox(text: "Selecciona un invernadero.")
                else if (selectedMap.capillas.isEmpty)
                  const _HintBox(text: "Este invernadero no tiene capillas.")
                else
                  _CapillasGrid(
                    map: selectedMap,
                    selectedCapId: _selectedCap?.id,
                    onSelect: _selectCap,
                  ),

                const SizedBox(height: 14),

                // =========================
                // 3) LÍNEA (con color)
                // =========================
                _SectionTitle(title: "3) Línea"),
                const SizedBox(height: 8),

                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (selectedMap == null) {
                        return const _HintBox(text: "Selecciona un invernadero.");
                      }
                      if (_selectedCap == null || _selectedCapIndexSorted == null) {
                        return const _HintBox(text: "Selecciona una capilla para ver sus líneas.");
                      }

                      final cap = _selectedCap!;
                      final capCode = "C${_selectedCapIndexSorted! + 1}";

                      final lines = List<int>.generate(cap.totalLineCount, (i) => cap.startLineNo + i);

                      return Stack(
                        children: [
                          GridView.builder(
                            padding: const EdgeInsets.only(bottom: 10),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 3.6,
                            ),
                            itemCount: lines.length,
                            itemBuilder: (_, i) {
                              final lineNo = lines[i];

                              // ✅ color alternado (verde/blanco) usando la misma lógica del mapa
                              final isGreen = selectedMap.isGreenLine(lineNo);

                              final bg = isGreen ? const Color(0xFFDFF2DF) : Colors.white;
                              final border = isGreen ? const Color(0xFF2E7D32) : Colors.black26;
                              final txt = isGreen ? const Color(0xFF2E7D32) : Colors.black87;

                              return OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: bg,
                                  foregroundColor: txt,
                                  side: BorderSide(color: border),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () => _startMonitoringPlaga(
                                          map: selectedMap,
                                          cap: cap,
                                          capIndexSorted: _selectedCapIndexSorted!,
                                          lineNo: lineNo,
                                        ),
                                child: Text(
                                  "$lineNo-$capCode",
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                ),
                              );
                            },
                          ),

                          if (_saving)
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: true,
                                child: Container(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  child: const Center(
                                    child: SizedBox(
                                      height: 26,
                                      width: 26,
                                      child: CircularProgressIndicator(strokeWidth: 2.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }
}

class _HintBox extends StatelessWidget {
  final String text;
  const _HintBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Text(text, style: TextStyle(color: Colors.black.withValues(alpha: 0.75), fontWeight: FontWeight.w700)),
    );
  }
}

class _CapillasGrid extends StatelessWidget {
  final GreenhouseMap map;
  final String? selectedCapId;
  final void Function(CapillaDef cap, int sortedIndex) onSelect;

  const _CapillasGrid({
    required this.map,
    required this.selectedCapId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final caps = [...map.capillas]..sort((a, b) => a.startLineNo.compareTo(b.startLineNo));

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.9,
      ),
      itemCount: caps.length,
      itemBuilder: (_, i) {
        final cap = caps[i];
        final capCode = "C${i + 1}";
        final selected = cap.id == selectedCapId;

        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? AppTheme.pepperGreen.withValues(alpha: 0.10) : Colors.white,
            side: BorderSide(color: selected ? AppTheme.pepperGreen : Colors.black26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => onSelect(cap, i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cap.name?.trim().isNotEmpty == true ? cap.name!.trim() : "(sin nombre)",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                "${cap.startLineNo}..${cap.endLineNo} · $capCode",
                style: TextStyle(color: Colors.black.withValues(alpha: 0.65), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }
}
