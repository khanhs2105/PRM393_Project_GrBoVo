import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';

/// Tạo nhóm mới (kèm thành viên) hoặc sửa tên/loại của nhóm có sẵn.
class GroupFormScreen extends StatefulWidget {
  final Group? group;
  const GroupFormScreen({super.key, this.group});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name);
  late String _type = widget.group?.type ?? 'meal';
  final _memberControllers = [TextEditingController(), TextEditingController()];

  bool get _isEdit => widget.group != null;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _memberControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isEdit) {
      await App.groups
          .update(widget.group!.copyWith(name: _name.text.trim(), type: _type));
      await App.activities.log(
        groupId: widget.group!.id,
        groupName: _name.text.trim(),
        kind: ActivityKind.groupEdited,
        message: 'Sửa thông tin nhóm',
      );
    } else {
      final names = _memberControllers
          .map((c) => c.text.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.length < 2) {
        showSnack(context, 'Nhóm cần ít nhất 2 người');
        return;
      }
      final id = await App.groups.create(
        Group(name: _name.text.trim(), type: _type, createdAt: DateTime.now()),
        [for (final n in names) Member(groupId: 0, name: n)],
      );
      await App.activities.log(
        groupId: id,
        groupName: _name.text.trim(),
        kind: ActivityKind.groupCreated,
        message: 'Tạo nhóm với ${names.join(', ')}',
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa nhóm' : 'Tạo nhóm')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Tên nhóm', hintText: 'Ví dụ: Phòng 302'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên nhóm' : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final e in groupTypes.entries)
                  ChoiceChip(
                    avatar: Icon(e.value.$2, size: 18),
                    label: Text(e.value.$1),
                    selected: _type == e.key,
                    onSelected: (_) => setState(() => _type = e.key),
                  ),
              ],
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 24),
              Text('Thành viên', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < _memberControllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _memberControllers[i],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: i == 0 ? 'Bạn (người giữ máy)' : 'Thành viên ${i + 1}',
                      prefixIcon: const Icon(Icons.person_outline),
                      suffixIcon: _memberControllers.length > 2
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() =>
                                  _memberControllers.removeAt(i).dispose()),
                            )
                          : null,
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _memberControllers.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Thêm người'),
              ),
              const Text(
                'Thông tin ngân hàng để nhận tiền có thể thêm sau trong tab Thành viên.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('Lưu')),
        ),
      ),
    );
  }
}
