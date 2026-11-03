import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logic/categories.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../data/group_repository.dart';
import '../models/activity.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pro_prompts.dart';
import '../widgets/ui.dart';
import '../widgets/app_icons.dart';

/// Thêm hoặc sửa một khoản chi.
///
/// Có 4 cách chia giống Splitwise: chia đều, theo số tiền, theo phần
/// (ví dụ 2:1:1), theo phần trăm.
class ExpenseFormScreen extends StatefulWidget {
  final int groupId;
  final Expense? expense;
  const ExpenseFormScreen({super.key, required this.groupId, this.expense});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.expense?.title);
  late final _amount = TextEditingController(
      text: widget.expense == null ? '' : '${widget.expense!.amount}');
  late final _note = TextEditingController(text: widget.expense?.note);

  Group? _group;
  List<Member> _members = [];
  int? _paidBy;
  final Set<int> _selected = {};
  late String _splitType = widget.expense?.splitType ?? SplitType.equal;

  /// Ô nhập số tiền từng người (kiểu theo số tiền).
  final Map<int, TextEditingController> _exact = {};

  /// Ô nhập % từng người (kiểu theo %).
  final Map<int, TextEditingController> _percent = {};

  /// Người đã tự gõ %. Phần còn lại tự chia đều cho những người khác.
  final Set<int> _percentLocked = {};

  /// Số phần của từng người (kiểu theo phần).
  final Map<int, int> _parts = {};

  /// Danh mục người dùng tự chọn. null: đoán theo nội dung.
  late ExpenseCategory? _category =
      categoryFromName(widget.expense?.category);
  String? _receiptPath;
  late DateTime _date = widget.expense?.date ?? DateTime.now();

  bool get _isEdit => widget.expense != null;
  int get _amountValue => parseVnd(_amount.text) ?? 0;
  ExpenseCategory get _shownCategory => _category ?? categorize(_title.text);

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _title.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final group = await App.groups.getById(widget.groupId);
    final members = await App.groups.members(widget.groupId);
    if (!mounted) return;
    if (members.isEmpty) {
      showSnack(context, 'Nhóm chưa có thành viên, thêm thành viên trước nhé');
      Navigator.pop(context);
      return;
    }
    final e = widget.expense;
    setState(() {
      _group = group;
      _members = members;
      _paidBy = e?.paidBy ?? members.first.id;
      _selected.addAll(e?.shares.keys ?? members.map((m) => m.id!));
      for (final m in members) {
        final id = m.id!;
        _exact[id] = TextEditingController(
            text: e?.splitType == SplitType.exact && e!.shares.containsKey(id)
                ? '${e.shares[id]}'
                : '')
          ..addListener(() => setState(() {}));
        _percent[id] = TextEditingController(
            text: e?.splitType == SplitType.percent && e!.weights[id] != null
                ? formatPercent(e.weights[id]!).replaceAll('%', '')
                : '')
          ..addListener(() => setState(() {}));
        _parts[id] = e?.splitType == SplitType.shares
            ? (e!.weights[id] ?? 1)
            : 1;
      }
      _receiptPath = e?.receiptPath;
      // Sửa khoản đã chia theo %: giữ nguyên % cũ của từng người, sửa một
      // người thì không tự chia lại làm mất % đã tùy chỉnh của người khác.
      if (e?.splitType == SplitType.percent) {
        _percentLocked.addAll(e!.weights.keys);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    for (final c in [..._exact.values, ..._percent.values]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- Tính phần từng người ----------

  int get _exactTotal =>
      _selected.fold(0, (sum, id) => sum + (parseVnd(_exact[id]!.text) ?? 0));

  Map<int, int> get _percentWeights => {
        for (final id in _selected) id: parsePercent(_percent[id]!.text) ?? 0,
      };

  int get _percentTotal => _percentWeights.values.fold(0, (a, b) => a + b);

  /// Người có ô % gõ sai (chữ, âm, hoặc lớn hơn 100). Ô trống không tính.
  /// Trước đây ô sai bị coi là 0% rồi chia lại cho người khác, tổng vẫn
  /// báo đủ 100% nên lưu được với phần 0 ₫.
  List<int> get _invalidPercentIds => [
        for (final id in _selected)
          if (_percent[id]!.text.trim().isNotEmpty &&
              parsePercent(_percent[id]!.text) == null)
            id,
      ];

  Map<int, int> get _partWeights => {
        for (final id in _selected) id: _parts[id] ?? 1,
      };

  int get _partsTotal => _partWeights.values.fold(0, (a, b) => a + b);

  /// Phần từng người theo cách chia đang chọn, null nếu chưa chia được.
  Map<int, int>? _preview() {
    if (_selected.isEmpty || _amountValue <= 0) return null;
    switch (_splitType) {
      case SplitType.equal:
        return splitEqual(_amountValue, _selected.toList(),
            remainderTo: _paidBy);
      case SplitType.exact:
        return {for (final id in _selected) id: parseVnd(_exact[id]!.text) ?? 0};
      case SplitType.shares:
        if (_partsTotal == 0) return null;
        return splitByWeights(_partWeights, _amountValue, remainderTo: _paidBy);
      default:
        if (_percentTotal == 0 || _invalidPercentIds.isNotEmpty) return null;
        return splitByWeights(_percentWeights, _amountValue,
            remainderTo: _paidBy);
    }
  }

  /// Báo lỗi nếu cách chia chưa hợp lệ, null là được.
  String? _splitError() {
    if (_selected.isEmpty) return 'Chọn ít nhất 1 người tham gia';
    switch (_splitType) {
      case SplitType.exact:
        final bad = [
          for (final id in _selected)
            if (_exact[id]!.text.trim().isNotEmpty &&
                parseVnd(_exact[id]!.text) == null)
              id,
        ];
        if (bad.isNotEmpty) {
          return 'Số tiền của ${bad.map(_memberName).join(', ')} không hợp lệ';
        }
        if (_exactTotal != _amountValue) {
          return 'Tổng các phần (${formatVnd(_exactTotal)}) phải bằng ${formatVnd(_amountValue)}';
        }
      case SplitType.shares:
        if (_partsTotal == 0) return 'Phải có ít nhất 1 phần';
      case SplitType.percent:
        final bad = _invalidPercentIds;
        if (bad.isNotEmpty) {
          final names = _members
              .where((m) => bad.contains(m.id))
              .map((m) => m.name)
              .join(', ');
          return 'Ô % của $names không hợp lệ (chỉ nhập số từ 0 đến 100)';
        }
        if (_percentTotal != percentScale) {
          return 'Tổng phải đúng 100% (đang ${formatPercent(_percentTotal)})';
        }
    }
    return null;
  }

  /// Chia đều 100% cho những người đang chọn (bỏ hết số đã tự gõ).
  void _fillEqualPercent() {
    _percentLocked.clear();
    _rebalancePercent();
  }

  /// Giữ nguyên % người dùng đã tự gõ, phần còn lại của 100% chia đều cho
  /// những người chưa gõ. Ví dụ 3 người, gõ A = 50% thì B, C tự thành 25%.
  void _rebalancePercent() {
    final ids = _members.map((m) => m.id!).where(_selected.contains).toList();
    _percentLocked.removeWhere((id) => !_selected.contains(id));
    final others = ids.where((id) => !_percentLocked.contains(id)).toList();
    if (others.isEmpty) return;
    final result = rebalancePercent(
      locked: {
        for (final id in _percentLocked) id: parsePercent(_percent[id]!.text) ?? 0,
      },
      others: others,
    );
    for (final id in others) {
      _percent[id]!.text = formatPercent(result[id]!).replaceAll('%', '');
    }
  }

  /// Bản Free chỉ chia đều. Khoản chi cũ đã chia kiểu khác thì vẫn giữ được
  /// kiểu đó khi sửa.
  bool _splitLocked(String type) =>
      type != SplitType.equal &&
      type != widget.expense?.splitType &&
      !App.plan.value.canSplitUnevenly;

  void _onPercentTyped(int id) {
    _percentLocked.add(id);
    // Ô đang gõ sai thì chưa chia lại, để người dùng thấy lỗi và sửa.
    if (_invalidPercentIds.isNotEmpty) return;
    _rebalancePercent();
  }

  /// Đổi người tham gia thì chia lại % (nếu đang chia theo %).
  void _afterSelectionChanged() {
    if (_splitType == SplitType.percent) _rebalancePercent();
  }

  // ---------- Hành động ----------

  Future<void> _pickReceipt(ImageSource source) async {
    if (!App.plan.value.canAttachReceipt) {
      final ok = await showProUpsell(context,
          title: 'Ảnh hóa đơn là tính năng Pro 😎',
          message: 'Đính kèm ảnh hóa đơn làm bằng chứng để cả nhóm cùng xem.');
      if (!ok || !mounted) return;
    }
    // image_picker tự xin quyền camera khi cần.
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (picked == null) return;
    // Chép ảnh vào thư mục của app, vì ảnh tạm của image_picker có thể bị xóa.
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path,
        'receipt_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
    await File(picked.path).copy(dest);
    setState(() => _receiptPath = dest);
  }

  String _memberName(int id) =>
      _members.firstWhere((m) => m.id == id).name;

  /// Người nhận phần lẻ khi chia đều: người trả nếu có tham gia, không thì
  /// người đầu tiên được chọn (giống splitEqual).
  String _remainderName() {
    if (_paidBy != null && _selected.contains(_paidBy)) {
      return _memberName(_paidBy!);
    }
    return _selected.isEmpty ? 'người trả' : _memberName(_selected.first);
  }

  /// Đang lưu: chặn bấm "Lưu" lần hai tạo bản ghi trùng (và pop 2 lần).
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _doSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _doSave() async {
    if (!_formKey.currentState!.validate()) return;
    final error = _splitError();
    if (error != null) {
      showSnack(context, error);
      return;
    }
    // Bỏ người có phần 0 ₫ (vd. được chọn nhưng để trống ô số tiền), để họ
    // không hiện trong khoản chi và nhật ký không đếm họ.
    final shares = Map.of(_preview()!)..removeWhere((_, v) => v == 0);
    if (shares.isEmpty) {
      showSnack(context, 'Chưa có ai phải trả phần nào');
      return;
    }
    final weights = switch (_splitType) {
      SplitType.shares => {
          for (final id in shares.keys) id: _partWeights[id]!,
        },
      SplitType.percent => {
          for (final id in shares.keys) id: _percentWeights[id]!,
        },
      _ => <int, int>{},
    };
    final note = _note.text.trim();
    final expense = Expense(
      id: widget.expense?.id,
      groupId: widget.groupId,
      title: _title.text.trim(),
      amount: _amountValue,
      paidBy: _paidBy!,
      splitType: _splitType,
      shares: shares,
      weights: weights,
      category: _category?.name,
      note: note.isEmpty ? null : note,
      receiptPath: _receiptPath,
      date: _date,
    );
    await App.expenses.save(expense);
    // Đổi hoặc bỏ ảnh hóa đơn khi sửa: xóa file ảnh cũ khỏi máy.
    final oldReceipt = widget.expense?.receiptPath;
    if (oldReceipt != null && oldReceipt != _receiptPath) {
      await deleteFileQuietly(oldReceipt);
    }
    await App.activities.log(
      groupId: widget.groupId,
      groupName: _group?.name ?? '',
      kind: _isEdit ? ActivityKind.expenseEdited : ActivityKind.expenseAdded,
      message: _isEdit
          ? 'Sửa khoản chi "${expense.title}"'
          : 'Thêm "${expense.title}", ${_memberName(expense.paidBy)} trả, '
              'chia ${shares.length} người',
      amount: expense.amount,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'Xóa khoản chi?',
        '"${widget.expense!.title}" sẽ bị xóa, số dư được tính lại.',
        ok: 'Xóa');
    if (!ok) return;
    await App.expenses.delete(widget.expense!.id!);
    await App.activities.log(
      groupId: widget.groupId,
      groupName: _group?.name ?? '',
      kind: ActivityKind.expenseDeleted,
      message: 'Xóa khoản chi "${widget.expense!.title}"',
      amount: widget.expense!.amount,
    );
    if (mounted) Navigator.pop(context, true);
  }

  // ---------- Giao diện ----------

  Widget _avatarChip(Member m,
      {required bool selected,
      required ValueChanged<bool> onSelected,
      bool filter = false}) {
    final avatar = MemberAvatar(m.name, radius: 12);
    return filter
        ? FilterChip(
            avatar: avatar,
            label: Text(m.name),
            selected: selected,
            showCheckmark: false,
            onSelected: onSelected,
          )
        : ChoiceChip(
            avatar: avatar,
            label: Text(m.name),
            selected: selected,
            showCheckmark: false,
            onSelected: onSelected,
          );
  }

  Widget _categoryPicker() {
    final shown = _shownCategory;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final c in ExpenseCategory.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(categoryStyle[c]!.$1,
                  size: 18, color: categoryStyle[c]!.$2),
              label: Text(categoryLabels[c]!),
              selected: shown == c,
              showCheckmark: false,
              onSelected: (_) => setState(() => _category = c),
            ),
          ),
      ]),
    );
  }

  /// Một dòng thành viên trong bảng chia (theo số tiền / phần / %).
  Widget _splitRow(Member m, Widget input, int? share) {
    final id = m.id!;
    final selected = _selected.contains(id);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        Checkbox(
          value: selected,
          onChanged: (v) {
            setState(() => v! ? _selected.add(id) : _selected.remove(id));
            _afterSelectionChanged();
          },
        ),
        MemberAvatar(m.name, radius: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (share != null && _splitType != SplitType.exact)
              Text(formatVnd(share),
                  style: TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
        input,
      ]),
    );
  }

  Widget _splitTotalRow(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ok ? AppTheme.owed : AppTheme.owe,
            )),
      ]),
    );
  }

  Widget _splitEditor(Map<int, int>? preview) {
    final scheme = Theme.of(context).colorScheme;
    switch (_splitType) {
      case SplitType.equal:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in _members)
              _avatarChip(m,
                  filter: true,
                  selected: _selected.contains(m.id),
                  onSelected: (v) => setState(() =>
                      v ? _selected.add(m.id!) : _selected.remove(m.id))),
          ]),
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Mỗi người ${formatVnd(_amountValue ~/ _selected.length)}'
                '${_amountValue % _selected.length == 0 ? '' : ' (phần lẻ ${_amountValue % _selected.length} ₫ tính cho ${_remainderName()})'}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ]);

      case SplitType.exact:
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              for (final m in _members)
                _splitRow(
                  m,
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _exact[m.id],
                      enabled: _selected.contains(m.id),
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                          isDense: true, hintText: '0', suffixText: '₫'),
                    ),
                  ),
                  null,
                ),
              _splitTotalRow(
                'Đã chia',
                '${formatVnd(_exactTotal)} / ${formatVnd(_amountValue)}',
                _exactTotal == _amountValue,
              ),
            ]),
          ),
        );

      case SplitType.shares:
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              for (final m in _members)
                _splitRow(
                  m,
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _selected.contains(m.id) &&
                              (_parts[m.id] ?? 1) > 1
                          ? () => setState(
                              () => _parts[m.id!] = (_parts[m.id] ?? 1) - 1)
                          : null,
                      icon: const Icon(AppIcons.circleMinus),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        _selected.contains(m.id) ? '${_parts[m.id] ?? 1}' : '0',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _selected.contains(m.id)
                          ? () => setState(
                              () => _parts[m.id!] = (_parts[m.id] ?? 1) + 1)
                          : null,
                      icon: const Icon(AppIcons.circlePlus),
                    ),
                  ]),
                  preview?[m.id],
                ),
              _splitTotalRow('Tổng số phần', '$_partsTotal phần', _partsTotal > 0),
            ]),
          ),
        );

      default:
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              for (final m in _members)
                _splitRow(
                  m,
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _percent[m.id],
                      enabled: _selected.contains(m.id),
                      // onChanged chỉ chạy khi người dùng gõ, không chạy khi
                      // app tự điền nên không bị lặp.
                      onChanged: (_) => _onPercentTyped(m.id!),
                      textAlign: TextAlign.end,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          isDense: true, hintText: '0', suffixText: '%'),
                    ),
                  ),
                  preview?[m.id],
                ),
              _splitTotalRow(
                'Tổng',
                '${formatPercent(_percentTotal)} / 100%',
                _percentTotal == percentScale,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _fillEqualPercent,
                  icon: const Icon(AppIcons.scale, size: 18),
                  label: const Text('Chia đều 100%'),
                ),
              ),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_members.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa khoản chi' : 'Thêm khoản chi'),
        actions: [
          if (_isEdit)
            IconButton(
                onPressed: _delete, icon: const Icon(AppIcons.trash2)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Ô số tiền lớn ở trên cùng, giống các app chia tiền phổ biến.
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(children: [
                  Row(children: [
                    IconTile.forCategory(_shownCategory),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                            hintText: 'Nội dung, ví dụ: Lẩu Thái'),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập nội dung'
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amount,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.text,
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary),
                    decoration: InputDecoration(
                      hintText: '0',
                      filled: false,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      suffixText: '₫',
                      helperText: _amountValue > 0
                          ? formatVnd(_amountValue)
                          : 'Gõ 150000, 150k hoặc 1.5tr',
                    ),
                    validator: (v) {
                      final x = parseVnd(v ?? '');
                      return (x == null || x <= 0)
                          ? 'Số tiền không hợp lệ'
                          : null;
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final quick in const [50000, 100000, 200000, 500000])
                        ActionChip(
                          label: Text(formatVnd(quick)),
                          onPressed: () => _amount.text = '$quick',
                        ),
                    ],
                  ),
                ]),
              ),
            ),
            SectionHeader('Danh mục',
                trailing: _category == null
                    ? Text('Tự đoán theo nội dung',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 11))
                    : TextButton(
                        onPressed: () => setState(() => _category = null),
                        child: const Text('Tự đoán'),
                      )),
            _categoryPicker(),
            const SectionHeader('Ai trả tiền?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in _members)
                _avatarChip(m,
                    selected: _paidBy == m.id,
                    onSelected: (_) => setState(() => _paidBy = m.id)),
            ]),
            SectionHeader('Chia cho ai?',
                trailing: TextButton(
                  onPressed: () {
                    setState(() => _selected.length == _members.length
                        ? _selected.clear()
                        : _selected.addAll(_members.map((m) => m.id!)));
                    _afterSelectionChanged();
                  },
                  child: Text(_selected.length == _members.length
                      ? 'Bỏ chọn hết'
                      : 'Chọn tất cả'),
                )),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                      value: SplitType.equal, label: Text('Đều')),
                  for (final (type, label) in const [
                    (SplitType.exact, 'Số tiền'),
                    (SplitType.shares, 'Phần'),
                    (SplitType.percent, '%'),
                  ])
                    ButtonSegment(
                      value: type,
                      label: Text(label),
                      icon: _splitLocked(type)
                          ? const Icon(AppIcons.lock, size: 14)
                          : null,
                    ),
                ],
                selected: {_splitType},
                onSelectionChanged: (v) async {
                  final type = v.first;
                  if (_splitLocked(type)) {
                    final ok = await showProUpsell(context,
                        title: 'Bill này có người ăn thêm?',
                        message: 'Chia theo số tiền, theo phần hoặc theo % '
                            'là tính năng Pro. Bản Free chia đều thoải mái.');
                    if (!ok || !mounted) return;
                  }
                  setState(() => _splitType = type);
                  if (_splitType == SplitType.percent) {
                    // Người tham gia có thể đã đổi ở tab khác: chia lại.
                    _percentTotal == 0
                        ? _fillEqualPercent()
                        : setState(_rebalancePercent);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _splitEditor(preview),
            const SectionHeader('Chi tiết'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                ListTile(
                  leading: const Icon(AppIcons.calendar),
                  title: const Text('Ngày'),
                  trailing: Text(formatDate(_date),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(AppIcons.notebookPen),
                      hintText: 'Ghi chú (không bắt buộc)',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<Plan>(
                  valueListenable: App.plan,
                  builder: (context, plan, _) => ListTile(
                    leading: const Icon(AppIcons.receipt),
                    title: const Text('Ảnh hóa đơn'),
                    subtitle: plan.canAttachReceipt
                        ? null
                        : const Text('Tính năng Pro (Chủ Nợ trở lên)'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!plan.canAttachReceipt)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(AppIcons.lock, size: 18),
                        ),
                      IconButton(
                        tooltip: 'Chụp ảnh',
                        onPressed: () => _pickReceipt(ImageSource.camera),
                        icon: const Icon(AppIcons.camera),
                      ),
                      IconButton(
                        tooltip: 'Chọn từ thư viện',
                        onPressed: () => _pickReceipt(ImageSource.gallery),
                        icon: const Icon(AppIcons.images),
                      ),
                    ]),
                  ),
                ),
                if (_receiptPath != null && File(_receiptPath!).existsSync())
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_receiptPath!),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          onPressed: () => setState(() => _receiptPath = null),
                          icon: const Icon(AppIcons.x),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(AppIcons.check),
            label: Text(_isEdit ? 'Lưu thay đổi' : 'Thêm khoản chi'),
          ),
        ),
      ),
    );
  }
}
