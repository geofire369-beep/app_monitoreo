import 'package:flutter/material.dart';

import './../../models/mapa_model.dart';
import './mapa_controller.dart';
import './map_widgets.dart';
import '../../../theme/app_theme.dart';

class MapaPage extends StatefulWidget {
  final String? mapId;
  const MapaPage({super.key, this.mapId});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  final controller = MapaController();

  bool _askedFirstCapilla = false;
  bool _loading = false;
  Object? _loadError;

  bool _capillasExpanded = false;
  bool _trampasExpanded = false;

  @override
  void initState() {
    super.initState();

    if (widget.mapId != null && widget.mapId!.trim().isNotEmpty) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadMap(widget.mapId!);
      });
    }
  }

  Future<void> _loadMap(String id) async {
    try {
      setState(() {
        _loading = true;
        _loadError = null;
      });
      await controller.loadFromFirestore(id);
    } catch (e) {
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final map = controller.map;

        if (!_loading && map != null && map.capillas.isEmpty && !_askedFirstCapilla) {
          _askedFirstCapilla = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showAddCapillaDialog(context);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(map?.name ?? (widget.mapId != null ? "Editar mapa" : "Crear mapa")),
            backgroundColor: AppTheme.pepperRed,
            foregroundColor: Colors.white,
            actions: [
              if (map != null)
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: "Guardar",
                  onPressed: () async {
                    try {
                      final id = await controller.saveToFirestore();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Guardado ✅ DocID: $id")),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error: $e")),
                      );
                    }
                  },
                )
            ],
          ),

          // ✅ COMO TU IMAGEN: DOS BOTONES GRANDES ABAJO, MITAD Y MITAD
          bottomNavigationBar: (map == null || _loading)
              ? null
              : SafeArea(
                  child: BottomAppBar(
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: controller.isTrapMode ? null : () => _showAddCapillaDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text("Agregar capilla"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: controller.isTrapMode ? null : () => controller.startTrapMode(),
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: const Text("Trampa"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_loadError != null)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Error al cargar: $_loadError"),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => _loadMap(widget.mapId!),
                              icon: const Icon(Icons.refresh),
                              label: const Text("Reintentar"),
                            ),
                          ],
                        ),
                      ),
                    )
                  : (map == null
                      ? _CreateMapWizard(
                          onCreate: ({
                            required String name,
                            required int postsNorth,
                            required int postsSouth,
                            required int firstLineNo,
                            required bool stripedLines,
                            required String stripedStart,
                            required NS lineStartSide,
                          }) {
                            controller.newMap(
                              name: name,
                              postsNorth: postsNorth,
                              postsSouth: postsSouth,
                              firstLineNo: firstLineNo,
                              stripedLines: stripedLines,
                              stripedStart: stripedStart,
                              lineStartSide: lineStartSide,
                            );
                          },
                        )
                      : _EditorBody(
                          controller: controller,
                          capillasExpanded: _capillasExpanded,
                          onToggleCapillas: (v) => setState(() => _capillasExpanded = v),
                          trampasExpanded: _trampasExpanded,
                          onToggleTrampas: (v) => setState(() => _trampasExpanded = v),
                        )),
        );
      },
    );
  }

  Future<void> _showAddCapillaDialog(BuildContext context) async {
    final map = controller.map!;
    final isFirst = map.capillas.isEmpty;

    final onlyNorth = map.postsNorth > 0 && map.postsSouth <= 0;
    final onlySouth = map.postsSouth > 0 && map.postsNorth <= 0;

    final nameCtrl = TextEditingController();
    final lineCountCtrl = TextEditingController(text: "12");
    final startLineCtrl = TextEditingController(text: "${map.firstLineNo}");

    CapSideMode mode = onlyNorth
        ? CapSideMode.northOnly
        : onlySouth
            ? CapSideMode.southOnly
            : CapSideMode.bothPaired;

    bool advanced = false;
    final untilCtrl = TextEditingController();
    CapSideMode remainder = CapSideMode.southOnly;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Agregar capilla"),
          content: StatefulBuilder(
            builder: (ctx, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nombre / número de capilla (opcional)",
                        hintText: "Ej: Capilla 5 o vacío",
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isFirst) ...[
                      TextField(
                        controller: startLineCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "¿Desde qué número empiezan las líneas?",
                          hintText: "Ej: 1",
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: lineCountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "¿Cuántas líneas tiene esta capilla?",
                        hintText: "Ej: 20",
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!(onlyNorth || onlySouth))
                      DropdownButtonFormField<CapSideMode>(
                        value: mode,
                        decoration: const InputDecoration(labelText: "Capilla aplica a"),
                        items: const [
                          DropdownMenuItem(
                            value: CapSideMode.bothPaired,
                            child: Text("Norte + Sur (según numeración del invernadero)"),
                          ),
                          DropdownMenuItem(
                            value: CapSideMode.northOnly,
                            child: Text("Solo Norte (corrida)"),
                          ),
                          DropdownMenuItem(
                            value: CapSideMode.southOnly,
                            child: Text("Solo Sur (corrida)"),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            mode = v!;
                            if (mode != CapSideMode.bothPaired) {
                              advanced = false;
                              untilCtrl.text = "";
                              remainder = CapSideMode.southOnly;
                            }
                          });
                        },
                      ),
                    if (!(onlyNorth || onlySouth) && mode == CapSideMode.bothPaired) ...[
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Configuración avanzada"),
                        subtitle: const Text("Parte N+S y el resto solo en un lado"),
                        value: advanced,
                        onChanged: (v) => setState(() => advanced = v),
                      ),
                      if (advanced) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: untilCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "¿Hasta qué número de línea es Norte + Sur?",
                            hintText: "Ej: 34",
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<CapSideMode>(
                          value: remainder,
                          decoration: const InputDecoration(labelText: "Después continúa en"),
                          items: const [
                            DropdownMenuItem(value: CapSideMode.southOnly, child: Text("Solo Sur")),
                            DropdownMenuItem(value: CapSideMode.northOnly, child: Text("Solo Norte")),
                          ],
                          onChanged: (v) => setState(() => remainder = v!),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Agregar")),
          ],
        );
      },
    );

    if (ok != true) return;

    final lineCount = int.tryParse(lineCountCtrl.text.trim()) ?? 0;
    if (lineCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La capilla debe tener al menos 1 línea")),
      );
      return;
    }

    final overrideStart = isFirst ? (int.tryParse(startLineCtrl.text.trim()) ?? map.firstLineNo) : null;

    final start = isFirst ? (overrideStart ?? map.firstLineNo) : (map.lastLineNo + 1);
    final end = start + lineCount - 1;

    int? bothUntil;
    if (advanced && mode == CapSideMode.bothPaired) {
      bothUntil = int.tryParse(untilCtrl.text.trim());
      bothUntil ??= end;
      if (bothUntil < start) bothUntil = start;
      if (bothUntil > end) bothUntil = end;
    }

    controller.addCapilla(
      name: nameCtrl.text,
      mode: mode,
      lineCount: lineCount,
      overrideStartLineNo: overrideStart,
      advanced: advanced && mode == CapSideMode.bothPaired,
      bothUntilLineNo: bothUntil,
      remainderMode: remainder,
    );
  }
}

// ========================= EDITOR BODY =========================

class _EditorBody extends StatelessWidget {
  final MapaController controller;

  final bool capillasExpanded;
  final ValueChanged<bool> onToggleCapillas;

  final bool trampasExpanded;
  final ValueChanged<bool> onToggleTrampas;

  const _EditorBody({
    required this.controller,
    required this.capillasExpanded,
    required this.onToggleCapillas,
    required this.trampasExpanded,
    required this.onToggleTrampas,
  });

  @override
  Widget build(BuildContext context) {
    final map = controller.map!;
    return Column(
      children: [
        _Toolbar(controller: controller),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: MapLayoutEditor(controller: controller),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: _CapillasPanel(
                  map: map,
                  controller: controller,
                  expanded: capillasExpanded,
                  onToggle: onToggleCapillas,
                  maxFactor: 0.26,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TrampasPanel(
                  map: map,
                  controller: controller,
                  expanded: trampasExpanded,
                  onToggle: onToggleTrampas,
                  maxFactor: 0.26,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ========================= TOOLBAR (AQUÍ VA LO DE TRAMPAS ARRIBA A LA DERECHA) =========================

class _Toolbar extends StatelessWidget {
  final MapaController controller;
  const _Toolbar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final addingTrap = controller.isTrapMode;
    final selectedCount = controller.draftTrapCells.length;

    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Text("Pintar:", style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            SegmentedButton<PaintTool>(
              segments: const [
                ButtonSegment(value: PaintTool.toggle, label: Text("Toggle")),
                ButtonSegment(value: PaintTool.activate, label: Text("Activar")),
                ButtonSegment(value: PaintTool.deactivate, label: Text("Desactivar")),
              ],
              selected: {controller.tool},
              onSelectionChanged: (s) => controller.setTool(s.first),
            ),

            const Spacer(),

            // ✅ AQUÍ, EXACTO DONDE TÚ PUSISTE EL TEXTO EN LA IMAGEN
            //    van los controles de trampas.
            if (addingTrap)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        "seleccionar casillas de trampa",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: Text(
                          "Seleccionadas: $selectedCount",
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: () => controller.cancelTrapMode(),
                        child: const Text("Cancelar"),
                      ),
                      ElevatedButton(
                        onPressed: selectedCount == 0
                            ? null
                            : () async {
                                final name = await _askTrapName(context, controller);
                                if (name == null) return;
                                controller.commitTrap(name);
                              },
                        child: const Text("Guardar trampa"),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askTrapName(BuildContext context, MapaController controller) async {
    final map = controller.map!;
    final suggested = "Trampa ${map.traps.length + 1}";
    final ctrl = TextEditingController(text: suggested);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Nombre de la trampa"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: "Nombre",
            hintText: "Ej: Trampa 7",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Guardar")),
        ],
      ),
    );

    if (ok != true) return null;
    final v = ctrl.text.trim();
    return v.isEmpty ? suggested : v;
  }
}

// ========================= CAPILLAS PANEL =========================

class _CapillasPanel extends StatelessWidget {
  final GreenhouseMap map;
  final MapaController controller;

  final bool expanded;
  final ValueChanged<bool> onToggle;

  final double maxFactor;

  const _CapillasPanel({
    required this.map,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.maxFactor,
  });

  String _segmentsLabel(CapillaDef cap) {
    if (cap.segments.isEmpty) return "Sin segmentos";
    return cap.segments.map((s) {
      if (s.mode == CapSideMode.bothPaired) return "N+S(${s.lineCount})";
      if (s.mode == CapSideMode.northOnly) return "N(${s.lineCount})";
      return "S(${s.lineCount})";
    }).join(" → ");
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * maxFactor;

    return Material(
      elevation: 6,
      color: Colors.white,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: expanded ? maxH : 56,
        child: Column(
          children: [
            InkWell(
              onTap: () => onToggle(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text("Capillas: ${map.capillas.length}", style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Icon(expanded ? Icons.expand_more : Icons.expand_less),
                  ],
                ),
              ),
            ),
            if (expanded) const Divider(height: 1),
            if (expanded)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: map.capillas.length,
                  itemBuilder: (_, i) {
                    final cap = map.capillas[i];
                    final isLast = i == map.capillas.length - 1;

                    return ListTile(
                      dense: true,
                      title: Text("${cap.name ?? "(sin nombre)"}   [${cap.startLineNo}..${cap.endLineNoResolved}]"),
                      subtitle: Text("Segmentos: ${_segmentsLabel(cap)}"),
                      trailing: isLast
                          ? IconButton(
                              tooltip: "Eliminar última capilla",
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => controller.deleteLastCapilla(),
                            )
                          : const Icon(Icons.lock_outline, color: Colors.black38),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ========================= TRAMPAS PANEL =========================

class _TrampasPanel extends StatelessWidget {
  final GreenhouseMap map;
  final MapaController controller;

  final bool expanded;
  final ValueChanged<bool> onToggle;

  final double maxFactor;

  const _TrampasPanel({
    required this.map,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.maxFactor,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * maxFactor;

    return Material(
      elevation: 6,
      color: Colors.white,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: expanded ? maxH : 56,
        child: Column(
          children: [
            InkWell(
              onTap: () => onToggle(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text("${map.traps.length} trampa${map.traps.length == 1 ? "" : "s"}",
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Icon(expanded ? Icons.expand_more : Icons.expand_less),
                  ],
                ),
              ),
            ),
            if (expanded) const Divider(height: 1),
            if (expanded)
              Expanded(
                child: map.traps.isEmpty
                    ? const Center(child: Text("Aún no hay trampas. Presiona “Trampa” abajo."))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: map.traps.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = map.traps[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text("Casillas: ${t.cells.length}"),
                            trailing: IconButton(
                              tooltip: "Eliminar trampa",
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => controller.deleteTrap(t.id),
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

// ========================= CREATE MAP WIZARD =========================

class _CreateMapWizard extends StatefulWidget {
  final void Function({
    required String name,
    required int postsNorth,
    required int postsSouth,
    required int firstLineNo,
    required bool stripedLines,
    required String stripedStart,
    required NS lineStartSide,
  }) onCreate;

  const _CreateMapWizard({required this.onCreate});

  @override
  State<_CreateMapWizard> createState() => _CreateMapWizardState();
}

class _CreateMapWizardState extends State<_CreateMapWizard> {
  final nameCtrl = TextEditingController(text: "Invernadero");
  final postsNCtrl = TextEditingController(text: "28");
  final postsSCtrl = TextEditingController(text: "28");
  final firstLineCtrl = TextEditingController(text: "1");

  bool stripedLines = true;
  String stripedStart = "WHITE";
  NS lineStartSide = NS.north;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    final pn = int.tryParse(postsNCtrl.text.trim()) ?? 0;
    final ps = int.tryParse(postsSCtrl.text.trim()) ?? 0;

    final onlyNorth = pn > 0 && ps <= 0;
    final onlySouth = ps > 0 && pn <= 0;
    final bothSides = pn > 0 && ps > 0;

    if (onlyNorth) lineStartSide = NS.north;
    if (onlySouth) lineStartSide = NS.south;

    final startSideLabel = lineStartSide == NS.north ? "NORTE" : "SUR";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Crear mapa", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Nombre del invernadero (obligatorio y único)",
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: postsNCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Postes Norte (0 si no hay)"),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: postsSCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Postes Sur (0 si no hay)"),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: firstLineCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "¿Desde qué número empiezan las líneas?"),
              ),
              const SizedBox(height: 12),
              if (bothSides) ...[
                DropdownButtonFormField<NS>(
                  value: lineStartSide,
                  decoration: const InputDecoration(
                    labelText: "¿En qué lado inicia la numeración?",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: NS.north, child: Text("Inicia en NORTE (línea inicial)")),
                    DropdownMenuItem(value: NS.south, child: Text("Inicia en SUR (línea inicial)")),
                  ],
                  onChanged: (v) => setState(() => lineStartSide = v ?? NS.north),
                ),
                const SizedBox(height: 12),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Líneas con patrón (blanco/verde)"),
                value: stripedLines,
                onChanged: (v) => setState(() => stripedLines = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: stripedStart,
                decoration: InputDecoration(
                  labelText: "¿Con qué color empieza la línea inicial ($startSideLabel)?",
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "WHITE", child: Text("Empieza en BLANCO")),
                  DropdownMenuItem(value: "GREEN", child: Text("Empieza en VERDE")),
                ],
                onChanged: (v) => setState(() => stripedStart = (v ?? "WHITE")),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("Crear"),
                  style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final pn2 = int.tryParse(postsNCtrl.text.trim()) ?? 0;
                    final ps2 = int.tryParse(postsSCtrl.text.trim()) ?? 0;
                    final first = int.tryParse(firstLineCtrl.text.trim()) ?? 1;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Escribe el nombre del invernadero")),
                      );
                      return;
                    }
                    if (pn2 <= 0 && ps2 <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Debes tener postes en Norte o en Sur (al menos uno).")),
                      );
                      return;
                    }

                    NS startSide = lineStartSide;
                    if (pn2 > 0 && ps2 <= 0) startSide = NS.north;
                    if (ps2 > 0 && pn2 <= 0) startSide = NS.south;

                    widget.onCreate(
                      name: name,
                      postsNorth: pn2,
                      postsSouth: ps2,
                      firstLineNo: first,
                      stripedLines: stripedLines,
                      stripedStart: stripedStart,
                      lineStartSide: startSide,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
