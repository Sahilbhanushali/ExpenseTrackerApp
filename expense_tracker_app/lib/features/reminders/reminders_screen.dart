import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/reminder.dart';
import 'reminders_controller.dart';

String _repeatLabel(ReminderRepeat repeat) => switch (repeat) {
  ReminderRepeat.none => 'One-time',
  ReminderRepeat.daily => 'Daily',
  ReminderRepeat.weekly => 'Weekly',
  ReminderRepeat.monthly => 'Monthly',
};

String _formatWhen(DateTime dt) {
  final now = DateTime.now();
  final date = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = date.difference(today).inDays;
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final timeStr = '$hour:$minute';
  if (diff == 0) return 'Today, $timeStr';
  if (diff == 1) return 'Tomorrow, $timeStr';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} · $timeStr';
}

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  Future<void> _showAddEdit(BuildContext context, {Reminder? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final noteController = TextEditingController(text: existing?.note ?? '');
    var dateTime =
        existing?.dateTime ?? DateTime.now().add(const Duration(hours: 1));
    var repeat = existing?.repeat ?? ReminderRepeat.none;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'New reminder' : 'Edit reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(_formatWhen(dateTime)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: dateTime,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(dateTime),
                    );
                    if (time == null) return;
                    setState(() {
                      dateTime = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<ReminderRepeat>(
                  segments: const [
                    ButtonSegment(
                      value: ReminderRepeat.none,
                      label: Text('Once'),
                    ),
                    ButtonSegment(
                      value: ReminderRepeat.daily,
                      label: Text('Daily'),
                    ),
                    ButtonSegment(
                      value: ReminderRepeat.weekly,
                      label: Text('Weekly'),
                    ),
                    ButtonSegment(
                      value: ReminderRepeat.monthly,
                      label: Text('Monthly'),
                    ),
                  ],
                  selected: {repeat},
                  onSelectionChanged: (s) => setState(() => repeat = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final note = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();
    final controller = context.read<RemindersController>();
    if (existing == null) {
      await controller.add(
        title: title,
        note: note,
        dateTime: dateTime,
        repeat: repeat,
      );
    } else {
      await controller.update(
        existing.copyWith(
          title: title,
          note: note,
          dateTime: dateTime,
          repeat: repeat,
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this reminder?'),
        content: Text('"${reminder.title}" will no longer notify you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<RemindersController>().remove(reminder.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<RemindersController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'reminders_add',
        onPressed: () => _showAddEdit(context),
        child: const Icon(Icons.add),
      ),
      body: reminders.reminders.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_outlined,
              message: 'No reminders yet. Add one to get notified.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              itemCount: reminders.reminders.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final r = reminders.reminders[i];
                return StaggeredListItem(
                  index: i,
                  child: AppCard(
                    child: ListRow(
                      icon: Icons.notifications_outlined,
                      iconColor: r.active ? context.palette.savings : null,
                      title: r.title,
                      subtitle:
                          '${_formatWhen(r.dateTime)} · ${_repeatLabel(r.repeat)}'
                          '${r.note?.isNotEmpty == true ? ' · ${r.note}' : ''}',
                      onTap: () => _showAddEdit(context, existing: r),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: r.active,
                            onChanged: (v) => reminders.toggleActive(r, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, r),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
