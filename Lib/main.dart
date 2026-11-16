import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ====================== أدوات مساعدة ======================

String normDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 0x30);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 0x30);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

int? parseInt(String s) =>
    int.tryParse(normDigits(s).replaceAll(RegExp(r'[\s,]'), ''));

double? parseDouble(String s) =>
    double.tryParse(normDigits(s).replaceAll(',', '.').replaceAll(' ', ''));

String fmt(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');

String fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

String fmtMoney(double v) => '${fmt(v.round())} دج';

Future<bool> confirm(BuildContext context, String msg) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد')),
      ],
    ),
  );
  return r ?? false;
}

IconData iconFor(String id) {
  switch (id) {
    case 'oil':
      return Icons.opacity;
    case 'oil_filter':
    case 'air_filter':
    case 'fuel_filter':
      return Icons.filter_alt;
    case 'cabin_filter':
      return Icons.ac_unit;
    case 'tires':
      return Icons.tire_repair;
    case 'brakes':
      return Icons.stop_circle;
    case 'spark':
      return Icons.flash_on;
    case 'battery':
      return Icons.battery_charging_full;
    case 'belt':
      return Icons.settings;
    default:
      return Icons.build;
  }
}

// ====================== النماذج ======================

class Item {
  final String id;
  String name;
  int intervalKm;
  int intervalMonths;

  Item({
    required this.id,
    required this.name,
    required this.intervalKm,
    required this.intervalMonths,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intervalKm': intervalKm,
        'intervalMonths': intervalMonths,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        intervalKm: (j['intervalKm'] as num?)?.toInt() ?? 0,
        intervalMonths: (j['intervalMonths'] as num?)?.toInt() ?? 0,
      );
}

class Service {
  final String itemId;
  final DateTime date;
  final int km;
  final double cost;
  final String note;

  Service({
    required this.itemId,
    required this.date,
    required this.km,
    required this.cost,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'date': date.toIso8601String(),
        'km': km,
        'cost': cost,
        'note': note,
      };

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        itemId: j['itemId'] as String,
        date: DateTime.parse(j['date'] as String),
        km: (j['km'] as num).toInt(),
        cost: (j['cost'] as num).toDouble(),
        note: j['note'] as String? ?? '',
      );
}

enum Level { overdue, soon, none, ok }

class Status {
  final Level level;
  final String text;
  const Status(this.level, this.text);

  Color get color {
    switch (level) {
      case Level.overdue:
        return Colors.red;
      case Level.soon:
        return Colors.orange;
      case Level.ok:
        return Colors.green;
      case Level.none:
        return Colors.grey;
    }
  }
}

List<Item> defaultItems() => [
      Item(id: 'oil', name: 'زيت المحرك', intervalKm: 10000, intervalMonths: 6),
      Item(id: 'oil_filter', name: 'فلتر الزيت', intervalKm: 10000, intervalMonths: 6),
      Item(id: 'air_filter', name: 'فلتر الهواء', intervalKm: 15000, intervalMonths: 12),
      Item(id: 'fuel_filter', name: 'فلتر الوقود (مازوط/بنزين)', intervalKm: 20000, intervalMonths: 12),
      Item(id: 'cabin_filter', name: 'فلتر المكيّف', intervalKm: 15000, intervalMonths: 12),
      Item(id: 'belt', name: 'سير/سلسلة التوزيع (لاشان)', intervalKm: 80000, intervalMonths: 60),
      Item(id: 'tires', name: 'العجلات', intervalKm: 40000, intervalMonths: 48),
      Item(id: 'brakes', name: 'الفرامل (بلاكات)', intervalKm: 30000, intervalMonths: 24),
      Item(id: 'spark', name: 'شمعات الإشعال', intervalKm: 30000, intervalMonths: 24),
      Item(id: 'battery', name: 'البطارية', intervalKm: 0, intervalMonths: 36),
    ];

// ====================== التخزين والمنطق ======================

class Store extends ChangeNotifier {
  final SharedPreferences prefs;
  String carName = 'سيارتي';
  int currentKm = 0;
  List<Item> items = [];
  List<Service> services = [];

  Store(this.prefs);

  static Future<Store> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = Store(prefs);
    final raw = prefs.getString('data');
    if (raw == null) {
      s.items = defaultItems();
    } else {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        s.carName = j['carName'] as String? ?? s.carName;
        s.currentKm = (j['currentKm'] as num?)?.toInt() ?? 0;
        s.items = (j['items'] as List)
            .map((e) => Item.fromJson(e as Map<String, dynamic>))
            .toList();
        s.services = (j['services'] as List)
            .map((e) => Service.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        s.items = defaultItems();
        s.services = [];
      }
    }
    return s;
  }

  void _save() {
    prefs.setString(
      'data',
      jsonEncode({
        'carName': carName,
        'currentKm': currentKm,
        'items': items.map((e) => e.toJson()).toList(),
        'services': services.map((e) => e.toJson()).toList(),
      }),
    );
    notifyListeners();
  }

  void setCar(String name, int km) {
    carName = name;
    currentKm = km;
    _save();
  }

  void addItem(Item i) {
    items.add(i);
    _save();
  }

  void updateItem() => _save();

  void deleteItem(String id) {
    items.removeWhere((e) => e.id == id);
    services.removeWhere((s) => s.itemId == id);
    _save();
  }

  void addService(Service s) {
    services.add(s);
    if (s.km > currentKm) currentKm = s.km;
    _save();
  }

  void deleteService(Service s) {
    services.remove(s);
    _save();
  }

  double get totalCost => services.fold<double>(0, (a, s) => a + s.cost);

  Item? itemById(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Service? lastService(String id) {
    Service? best;
    for (final s in services) {
      if (s.itemId != id) continue;
      if (best == null ||
          s.date.isAfter(best.date) ||
          (s.date == best.date && s.km > best.km)) {
        best = s;
      }
    }
    return best;
  }

  Status statusOf(Item it) {
    final last = lastService(it.id);
    if (last == null) {
      return const Status(Level.none, 'لم تُسجَّل أي صيانة بعد');
    }
    int? remKm;
    int? remDays;
    if (it.intervalKm > 0) {
      remKm = last.km + it.intervalKm - currentKm;
    }
    if (it.intervalMonths > 0) {
      final next = DateTime(
          last.date.year, last.date.month + it.intervalMonths, last.date.day);
      remDays = next.difference(DateTime.now()).inDays;
    }
    if (remKm == null && remDays == null) {
      return const Status(Level.ok, 'بدون موعد محدد');
    }
    final parts = <String>[];
    if (remKm != null) {
      parts.add(remKm < 0 ? 'تجاوزت ${fmt(-remKm)} كم' : 'باقي ${fmt(remKm)} كم');
    }
    if (remDays != null) {
      parts.add(remDays < 0 ? 'تجاوزت ${-remDays} يوم' : 'باقي $remDays يوم');
    }
    final overdue =
        (remKm != null && remKm < 0) || (remDays != null && remDays < 0);
    final soon = (remKm != null && remKm <= it.intervalKm ~/ 10) ||
        (remDays != null && remDays <= 30);
    final level = overdue ? Level.overdue : (soon ? Level.soon : Level.ok);
    return Status(level, parts.join(' • '));
  }
}

// ====================== التطبيق ======================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.load();
  runApp(CarApp(store: store));
}

class CarApp extends StatelessWidget {
  final Store store;
  const CarApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صيانة سيارتي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
      ),
      home: HomePage(store: store),
    );
  }
}

class HomePage extends StatefulWidget {
  final Store store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(tab == 0 ? 'صيانة سيارتي' : 'سجل الصيانة'),
          ),
          body: tab == 0 ? _itemsTab(context) : _historyTab(context),
          floatingActionButton: tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => ItemDialog(store: store),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة بند'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.build), label: 'الصيانات'),
              NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
            ],
          ),
        );
      },
    );
  }

  Widget _itemsTab(BuildContext context) {
    final store = widget.store;
    final entries = store.items
        .map((it) => MapEntry(it, store.statusOf(it)))
        .toList()
      ..sort((a, b) => a.value.level.index.compareTo(b.value.level.index));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car, size: 36),
            title: Text(store.carName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('العداد: ${fmt(store.currentKm)} كم'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => CarDialog(store: store),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        for (final e in entries)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: e.value.color.withOpacity(0.15),
                child: Icon(iconFor(e.key.id), color: e.value.color),
              ),
              title: Text(e.key.name),
              subtitle:
                  Text(e.value.text, style: TextStyle(color: e.value.color)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemPage(store: store, itemId: e.key.id),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _historyTab(BuildContext context) {
    final store = widget.store;
    final list = [...store.services]..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      return const Center(child: Text('لا توجد صيانات مسجلة بعد'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.payments),
            title: const Text('مجموع المصاريف'),
            trailing: Text(
              fmtMoney(store.totalCost),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        for (final s in list) _serviceTile(context, store, s),
      ],
    );
  }
}

Widget _serviceTile(BuildContext context, Store store, Service s) {
  final item = store.itemById(s.itemId);
  final sub = StringBuffer('${fmtDate(s.date)} • ${fmt(s.km)} كم');
  if (s.note.isNotEmpty) sub.write(' • ${s.note}');
  return Card(
    child: ListTile(
      leading: Icon(iconFor(s.itemId)),
      title: Text(item?.name ?? 'بند محذوف'),
      subtitle: Text(sub.toString()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.cost > 0) Text(fmtMoney(s.cost)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'حذف هذا التسجيل؟')) {
                store.deleteService(s);
              }
            },
          ),
        ],
      ),
    ),
  );
}

// ====================== صفحة البند ======================

class ItemPage extends StatelessWidget {
  final Store store;
  final String itemId;
  const ItemPage({super.key, required this.store, required this.itemId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final it = store.itemById(itemId);
        if (it == null) return const Scaffold(body: SizedBox());
        final st = store.statusOf(it);
        final last = store.lastService(it.id);
        final hist = store.services.where((s) => s.itemId == it.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final intervals = <String>[];
        if (it.intervalKm > 0) intervals.add('كل ${fmt(it.intervalKm)} كم');
        if (it.intervalMonths > 0) intervals.add('كل ${it.intervalMonths} شهر');

        return Scaffold(
          appBar: AppBar(
            title: Text(it.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => ItemDialog(store: store, item: it),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, 'حذف هذا البند وكل سجلاته؟')) {
                    store.deleteItem(it.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st.text,
                        style: TextStyle(
                            color: st.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'الفاصل: ${intervals.isEmpty ? 'غير محدد' : intervals.join(' أو ')}'),
                      if (last != null)
                        Text(
                            'آخر صيانة: ${fmtDate(last.date)} • ${fmt(last.km)} كم'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ServiceForm(store: store, item: it),
                ),
                icon: const Icon(Icons.add_task),
                label: const Text('سجّل صيانة جديدة'),
              ),
              const SizedBox(height: 16),
              const Text('السجل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              if (hist.isEmpty) const Text('لا يوجد تسجيل بعد'),
              for (final s in hist) _serviceTile(context, store, s),
            ],
          ),
        );
      },
    );
  }
}

// ====================== النماذج (Forms) ======================

class ServiceForm extends StatefulWidget {
  final Store store;
  final Item item;
  const ServiceForm({super.key, required this.store, required this.item});

  @override
  State<ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<ServiceForm> {
  late final TextEditingController km =
      TextEditingController(text: widget.store.currentKm.toString());
  final TextEditingController cost = TextEditingController();
  final TextEditingController note = TextEditingController();
  DateTime date = DateTime.now();
  String? error;

  @override
  void dispose() {
    km.dispose();
    cost.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => date = d);
  }

  void _save() {
    final k = parseInt(km.text.trim());
    if (k == null || k < 0) {
      setState(() => error = 'أدخل العداد بأرقام صحيحة');
      return;
    }
    final c = cost.text.trim().isEmpty ? 0.0 : parseDouble(cost.text.trim());
    if (c == null || c < 0) {
      setState(() => error = 'السعر غير صحيح');
      return;
    }
    widget.store.addService(Service(
      itemId: widget.item.id,
      date: date,
      km: k,
      cost: c,
      note: note.text.trim(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تسجيل: ${widget.item.name}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.event),
              label: Text('التاريخ: ${fmtDate(date)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: km,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'العداد (كم)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'السعر (دج) - اختياري',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                  labelText: 'ملاحظة - اختياري', border: OutlineInputBorder()),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}

class ItemDialog extends StatefulWidget {
  final Store store;
  final Item? item;
  const ItemDialog({super.key, required this.store, this.item});

  @override
  State<ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late final TextEditingController name =
      TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController km = TextEditingController(
      text: widget.item == null ? '' : widget.item!.intervalKm.toString());
  late final TextEditingController months = TextEditingController(
      text: widget.item == null ? '' : widget.item!.intervalMonths.toString());
  String? error;

  @override
  void dispose() {
    name.dispose();
    km.dispose();
    months.dispose();
    super.dispose();
  }

  void _save() {
    final n = name.text.trim();
    final k = km.text.trim().isEmpty ? 0 : parseInt(km.text.trim());
    final m = months.text.trim().isEmpty ? 0 : parseInt(months.text.trim());
    if (n.isEmpty) {
      setState(() => error = 'أدخل اسم البند');
      return;
    }
    if (k == null || m == null || k < 0 || m < 0) {
      setState(() => error = 'أدخل أرقاماً صحيحة');
      return;
    }
    if (k == 0 && m == 0) {
      setState(() => error = 'حدّد فاصلاً بالكيلومتر أو بالأشهر');
      return;
    }
    final it = widget.item;
    if (it == null) {
      widget.store.addItem(Item(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: n,
        intervalKm: k,
        intervalMonths: m,
      ));
    } else {
      it.name = n;
      it.intervalKm = k;
      it.intervalMonths = m;
      widget.store.updateItem();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'بند جديد' : 'تعديل البند'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: km,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'كل كم كيلومتر (0 = بدون)'),
            ),
            TextField(
              controller: months,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'كل كم شهر (0 = بدون)'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

class CarDialog extends StatefulWidget {
  final Store store;
  const CarDialog({super.key, required this.store});

  @override
  State<CarDialog> createState() => _CarDialogState();
}

class _CarDialogState extends State<CarDialog> {
  late final TextEditingController name =
      TextEditingController(text: widget.store.carName);
  late final TextEditingController km =
      TextEditingController(text: widget.store.currentKm.toString());
  String? error;

  @override
  void dispose() {
    name.dispose();
    km.dispose();
    super.dispose();
  }

  void _save() {
    final k = parseInt(km.text.trim());
    if (k == null || k < 0) {
      setState(() => error = 'أدخل العداد بأرقام صحيحة');
      return;
    }
    final n = name.text.trim().isEmpty ? 'سيارتي' : name.text.trim();
    widget.store.setCar(n, k);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('بيانات السيارة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'اسم السيارة (مثال: كليو 2018)'),
            ),
            TextField(
              controller: km,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'العداد الحالي (كم)'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}
