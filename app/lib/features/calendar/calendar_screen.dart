import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';

class CalendarEvent {
  const CalendarEvent({required this.id, required this.title, required this.startsAt, required this.endsAt, this.location});

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        location: json['location'] as String?,
      );

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? location;
}

final eventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final now = DateTime.now().toUtc();
  final res = await ref.watch(apiClientProvider).get('/api/calendar/events', query: {
    'from': now.subtract(const Duration(days: 1)).toIso8601String(),
    'to': now.add(const Duration(days: 60)).toIso8601String(),
  });
  return (res['events'] as List).cast<Map<String, dynamic>>().map(CalendarEvent.fromJson).toList();
});

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  Future<void> _addEvent(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    var day = DateTime.now();
    var time = TimeOfDay.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Neuer Termin'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Titel')),
            const SizedBox(height: NexusTokens.s3),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(DateFormat.yMMMd().format(day)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => day = picked);
                  },
                ),
              ),
              const SizedBox(width: NexusTokens.s2),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(time.format(context)),
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: time);
                    if (picked != null) setState(() => time = picked);
                  },
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (saved != true || title.text.trim().isEmpty) return;
    final start = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await ref.read(apiClientProvider).post('/api/calendar/events', {
      'title': title.text.trim(),
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });
    ref.invalidate(eventsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kalender')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEvent(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Termin'),
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) return const Center(child: Text('Keine anstehenden Termine'));
          final byDay = <String, List<CalendarEvent>>{};
          for (final e in items) {
            byDay.putIfAbsent(DateFormat.yMMMMEEEEd().format(e.startsAt), () => []).add(e);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final entry in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(NexusTokens.s4, NexusTokens.s4, NexusTokens.s4, NexusTokens.s1),
                  child: Text(entry.key, style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final event in entry.value)
                  ListTile(
                    leading: Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    title: Text(event.title),
                    subtitle: Text(
                      '${DateFormat.Hm().format(event.startsAt)} – ${DateFormat.Hm().format(event.endsAt)}'
                      '${event.location != null ? ' · ${event.location}' : ''}',
                    ),
                    onLongPress: () async {
                      await ref.read(apiClientProvider).delete('/api/calendar/events/${event.id}');
                      ref.invalidate(eventsProvider);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
