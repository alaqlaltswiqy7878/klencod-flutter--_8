import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const Color appSeed = Color(0xFF6750A4);
const String appStorageKey = 'daily_planner_tasks_v1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const DailyPlannerApp());
}

class DailyPlannerApp extends StatelessWidget {
  const DailyPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'جدولي اليومي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: appSeed),
        scaffoldBackgroundColor: const Color(0xFFF7F5FA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8E3EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: appSeed, width: 1.5),
          ),
        ),
      ),
      home: const PlannerHomePage(),
    );
  }
}

enum TaskStatus { unset, completed, incomplete }

class PlannerTask {
  PlannerTask({
    required this.id,
    required this.dayKey,
    required this.text,
    required this.colorValue,
    this.startMinutes,
    this.status = TaskStatus.unset,
    this.dailyRepeat = false,
  });

  final String id;
  final String dayKey;
  String text;
  int colorValue;
  int? startMinutes;
  TaskStatus status;
  bool dailyRepeat;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayKey': dayKey,
        'text': text,
        'colorValue': colorValue,
        'startMinutes': startMinutes,
        'status': status.name,
        'dailyRepeat': dailyRepeat,
      };

  factory PlannerTask.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'unset';
    return PlannerTask(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      dayKey: json['dayKey'] as String? ?? dateKey(DateTime.now()),
      text: json['text'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? 0xFFEDE7F6,
      startMinutes: json['startMinutes'] as int?,
      status: TaskStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => TaskStatus.unset,
      ),
      dailyRepeat: json['dailyRepeat'] as bool? ?? false,
    );
  }

  PlannerTask copyForDay(String newDayKey) => PlannerTask(
        id: '${id}_$newDayKey',
        dayKey: newDayKey,
        text: text,
        colorValue: colorValue,
        startMinutes: startMinutes,
        status: TaskStatus.unset,
        dailyRepeat: true,
      );
}

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime dateFromKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String arabicDate(DateTime date) {
  const weekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'
  ];
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];
  final weekday = weekdays[date.weekday - 1];
  return '$weekday، ${date.day} ${months[date.month - 1]} ${date.year}';
}

String timeLabel(int? minutes) {
  if (minutes == null) return 'بدون وقت';
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  final suffix = hour >= 12 ? 'م' : 'ص';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

class TaskRepository {
  Future<List<PlannerTask>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(appStorageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PlannerTask.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<PlannerTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      appStorageKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // The planner remains usable if notification initialization is unavailable.
    }
  }

  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> scheduleTask(PlannerTask task) async {
    if (!_initialized || task.startMinutes == null || task.text.trim().isEmpty) {
      return;
    }
    final now = DateTime.now();
    final day = dateFromKey(task.dayKey);
    final scheduled = DateTime(
      day.year, day.month, day.day,
      task.startMinutes! ~/ 60, task.startMinutes! % 60,
    );
    if (!scheduled.isAfter(now)) return;
    try {
      await _plugin.zonedSchedule(
        task.id.hashCode & 0x7fffffff,
        'تذكير بمهمة',
        task.text.trim(),
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_planner_tasks',
            'تنبيهات المهام',
            channelDescription: 'تذكيرات أوقات المهام في الجدول اليومي',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.id,
      );
    } catch (_) {
      // The task is saved even if Android blocks or rejects a reminder.
    }
  }

  Future<void> cancelTask(PlannerTask task) async {
    try {
      await _plugin.cancel(task.id.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage> {
  final TaskRepository _repository = TaskRepository();
  final List<PlannerTask> _tasks = [];
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _notificationsEnabled = true;

  static const List<Color> _taskColors = [
    Color(0xFFEDE7F6),
    Color(0xFFE3F2FD),
    Color(0xFFE8F5E9),
    Color(0xFFFFF3E0),
    Color(0xFFFCE4EC),
    Color(0xFFE0F2F1),
    Color(0xFFFFF9C4),
    Color(0xFFECEFF1),
  ];

  String get _selectedKey => dateKey(_selectedDate);

  List<PlannerTask> get _dayTasks =>
      _tasks.where((task) => task.dayKey == _selectedKey).toList()
        ..sort((a, b) {
          if (a.startMinutes == null && b.startMinutes == null) return 0;
          if (a.startMinutes == null) return 1;
          if (b.startMinutes == null) return -1;
          return a.startMinutes!.compareTo(b.startMinutes!);
        });

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final loaded = await _repository.load();
    if (!mounted) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(loaded);
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await _repository.save(_tasks);
  }

  Future<void> _addTask() async {
    final task = PlannerTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dayKey: _selectedKey,
      text: '',
      colorValue: _taskColors[0].value,
    );
    setState(() => _tasks.add(task));
    await _persist();
    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) {
        // The new card is inserted immediately into the current day.
      }
    }
  }

  Future<void> _deleteTask(PlannerTask task) async {
    await NotificationService.instance.cancelTask(task);
    setState(() => _tasks.removeWhere((item) => item.id == task.id));
    await _persist();
  }

  Future<void> _updateTask(PlannerTask task) async {
    await _persist();
    if (_notificationsEnabled) {
      await NotificationService.instance.cancelTask(task);
      await NotificationService.instance.scheduleTask(task);
    }
  }

  Future<void> _changeDay(int amount) async {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: amount)));
    await _ensureDailyRepeats();
  }

  Future<void> _ensureDailyRepeats() async {
    final key = _selectedKey;
    final already = _tasks.where((task) => task.dayKey == key).toList();
    final repeatSources = _tasks
        .where((task) => task.dailyRepeat && task.dayKey != key)
        .toList();
    for (final source in repeatSources) {
      final copyId = '${source.id}_$key';
      if (!already.any((task) => task.id == copyId) &&
          !_tasks.any((task) => task.id == copyId)) {
        _tasks.add(source.copyForDay(key));
      }
    }
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _chooseTime(PlannerTask task) async {
    final initial = task.startMinutes == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(
            hour: task.startMinutes! ~/ 60,
            minute: task.startMinutes! % 60,
          );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'اختر وقت بداية المهمة',
    );
    if (picked == null) return;
    setState(() => task.startMinutes = picked.hour * 60 + picked.minute);
    await _updateTask(task);
  }

  Future<void> _chooseColor(PlannerTask task) async {
    final chosen = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: _taskColors.map((color) {
            return InkWell(
              onTap: () => Navigator.pop(context, color),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
                child: task.colorValue == color.value
                    ? const Icon(Icons.check, color: Colors.black87)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => task.colorValue = chosen.value);
    await _updateTask(task);
  }

  Future<void> _changeStatus(PlannerTask task, TaskStatus? status) async {
    if (status == null) return;
    setState(() => task.status = status);
    await _updateTask(task);
  }

  Future<void> _toggleRepeat(PlannerTask task, bool value) async {
    setState(() => task.dailyRepeat = value);
    await _updateTask(task);
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قد تحتاج إلى السماح بالإشعارات من إعدادات الهاتف.')),
        );
      }
    } else {
      await NotificationService.instance.cancelAll();
    }
    setState(() => _notificationsEnabled = value);
    if (value) {
      for (final task in _dayTasks) {
        await NotificationService.instance.scheduleTask(task);
      }
    }
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, sheetSetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('الإعدادات',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تفعيل إشعارات المهام'),
                subtitle: const Text('تذكير محلي عند وقت بداية المهمة'),
                value: _notificationsEnabled,
                onChanged: (value) async {
                  await _toggleNotifications(value);
                  sheetSetState(() {});
                },
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('حول التطبيق'),
                subtitle: Text('جدولي اليومي — المطور: شرف علي شرف'),
              ),
              const SizedBox(height: 8),
              const Text(
                'تعمل المهام والتخزين محليًا. قد تتأثر دقة التنبيهات بقيود البطارية وإعدادات Android.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<PlannerTask> tasks, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAE5F0)),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(icon, color: appSeed),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xFFEDE7F6),
          child: Text('${tasks.length}', style: const TextStyle(fontSize: 12)),
        ),
        children: tasks.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Text('لا توجد مهام في هذا القسم',
                      style: TextStyle(color: Colors.black54)),
                )
              ]
            : tasks.map((task) => ListTile(
                title: Text(
                  task.text.trim().isEmpty ? 'مهمة بدون عنوان' : task.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(timeLabel(task.startMinutes)),
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: Color(task.colorValue),
                ),
              )).toList(),
      ),
    );
  }

  Widget _taskCard(PlannerTask task, {bool compact = false}) {
    final color = Color(task.colorValue);
    return Card(
      margin: EdgeInsets.fromLTRB(compact ? 12 : 0, 5, compact ? 12 : 0, 7),
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextFormField(
              key: ValueKey('task_text_${task.id}'),
              initialValue: task.text,
              minLines: 1,
              maxLines: 5,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'اكتب المهمة هنا...',
                hintStyle: TextStyle(color: Colors.black.withOpacity(0.45)),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                task.text = value;
                _persist();
              },
              onEditingComplete: () => _updateTask(task),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule, size: 17, color: Colors.black.withOpacity(0.65)),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: () => _chooseTime(task),
                    child: Text(
                      timeLabel(task.startMinutes),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'اختيار اللون',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _chooseColor(task),
                  icon: const Icon(Icons.palette_outlined, size: 20),
                ),
                PopupMenuButton<TaskStatus>(
                  tooltip: 'حالة المهمة',
                  initialValue: task.status,
                  onSelected: (value) => _changeStatus(task, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: TaskStatus.unset, child: Text('بدون تحديد الحالة')),
                    PopupMenuItem(value: TaskStatus.completed, child: Text('مكتملة')),
                    PopupMenuItem(value: TaskStatus.incomplete, child: Text('غير مكتملة')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          task.status == TaskStatus.completed
                              ? Icons.check_circle
                              : task.status == TaskStatus.incomplete
                                  ? Icons.cancel_outlined
                                  : Icons.radio_button_unchecked,
                          size: 19,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.status == TaskStatus.completed
                              ? 'مكتملة'
                              : task.status == TaskStatus.incomplete
                                  ? 'غير مكتملة'
                                  : 'الحالة',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف المهمة',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(task),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            if (!compact)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 30,
                      child: Row(
                        children: [
                          Checkbox(
                            value: task.dailyRepeat,
                            visualDensity: VisualDensity.compact,
                            onChanged: (value) =>
                                _toggleRepeat(task, value ?? false),
                          ),
                          const Text('تتكرر يوميًا', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PlannerTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المهمة؟'),
        content: const Text('لن تظهر هذه المهمة في جدول هذا اليوم بعد حذفها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteTask(task);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _dayTasks;
    final unset = tasks.where((t) => t.status == TaskStatus.unset).toList();
    final completed = tasks.where((t) => t.status == TaskStatus.completed).toList();
    final incomplete = tasks.where((t) => t.status == TaskStatus.incomplete).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('جدولي اليومي', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: const Color(0xFFF7F5FA),
          actions: [
            IconButton(
              tooltip: 'الإعدادات',
              onPressed: _showSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFEAE5F0)),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'اليوم السابق',
                              onPressed: () => _changeDay(-1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    helpText: 'اختر اليوم',
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedDate = picked);
                                    await _ensureDailyRepeats();
                                  }
                                },
                                child: Column(
                                  children: [
                                    Text(
                                      dateKey(_selectedDate) == dateKey(DateTime.now())
                                          ? 'اليوم'
                                          : dateKey(_selectedDate) == dateKey(DateTime.now().add(const Duration(days: 1)))
                                              ? 'غدًا'
                                              : 'التاريخ المحدد',
                                      style: const TextStyle(
                                        color: appSeed,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      arabicDate(_selectedDate),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'اليوم التالي',
                              onPressed: () => _changeDay(1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6750A4), Color(0xFF8A73C5)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('خطوتك القادمة تبدأ الآن',
                                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  SizedBox(height: 5),
                                  Text('ماذا ستنجز اليوم؟',
                                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white24,
                              child: Text('${tasks.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('مهام اليوم',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                              Text('${tasks.length} مهمة',
                                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (tasks.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFEAE5F0)),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.edit_calendar_outlined, size: 38, color: appSeed),
                                  SizedBox(height: 8),
                                  Text('لا توجد مهام بعد', style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(height: 4),
                                  Text('اضغط «إضافة مهمة» لكتابة أول مهمة لك.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.black54)),
                                ],
                              ),
                            ),
                          ...tasks.map((task) => _taskCard(task)),
                          const SizedBox(height: 10),
                          const Text('ملخص اليوم',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          _buildSection('مهام لم تُحدَّد حالتها', unset, Icons.radio_button_unchecked),
                          _buildSection('المهام المكتملة', completed, Icons.check_circle_outline),
                          _buildSection('المهام غير المكتملة', incomplete, Icons.highlight_off),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addTask,
          icon: const Icon(Icons.add),
          label: const Text('إضافة مهمة'),
        ),
      ),
    );
  }
}