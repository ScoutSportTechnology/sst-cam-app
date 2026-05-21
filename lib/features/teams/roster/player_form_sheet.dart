import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/team.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';

/// Shows the player form. Returns the entered draft, or null on cancel.
/// Pass `existing` to prefill for edit; the caller decides whether to add
/// or update based on whether `existing` was provided.
Future<PlayerDraft?> showPlayerFormSheet(
  BuildContext context, {
  Player? existing,
  Set<int> takenNumbers = const {},
}) {
  return showModalBottomSheet<PlayerDraft>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PlayerForm(existing: existing, takenNumbers: takenNumbers),
    ),
  );
}

class _PlayerForm extends StatefulWidget {
  const _PlayerForm({this.existing, this.takenNumbers = const {}});
  final Player? existing;
  final Set<int> takenNumbers;

  @override
  State<_PlayerForm> createState() => _PlayerFormState();
}

class _PlayerFormState extends State<_PlayerForm> {
  late final TextEditingController _name;
  late final TextEditingController _number;
  late String _position;
  late bool _captain;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _number = TextEditingController(text: p == null ? '' : '${p.number}');
    _position = p?.position ?? kPlayerPositions.first;
    _captain = p?.captain ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final numberStr = _number.text.trim();
    final number = int.tryParse(numberStr);
    if (name.isEmpty) {
      setState(() => _error = 'Player name is required');
      return;
    }
    if (number == null || number < 0 || number > 99) {
      setState(() => _error = 'Jersey number must be 0–99');
      return;
    }
    final isOwn = widget.existing?.number == number;
    if (!isOwn && widget.takenNumbers.contains(number)) {
      setState(() => _error = 'Jersey #$number is already on this team');
      return;
    }
    Navigator.of(context).pop(
      PlayerDraft(
        number: number,
        name: name,
        position: _position,
        captain: _captain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: T.fillMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEdit ? 'Edit player' : 'Add player',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: _LabeledField(
                    label: 'Number',
                    controller: _number,
                    hint: '07',
                    autofocus: !isEdit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabeledField(
                    label: 'Name',
                    controller: _name,
                    hint: 'A. Patel',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const WfNote('POSITION'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kPlayerPositions
                  .map(
                    (p) => GestureDetector(
                      onTap: () => setState(() => _position = p),
                      child: AnimatedContainer(
                        duration: T.fast,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _position == p ? T.accent : T.fillSoft,
                          border: Border.all(
                            color: _position == p ? T.accent : T.hair,
                          ),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _position == p ? T.accentInk : T.ink2,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Switch.adaptive(
                  value: _captain,
                  onChanged: (v) => setState(() => _captain = v),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Captain',
                  style: TextStyle(
                    color: T.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(color: T.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: WfButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WfButton(
                    label: isEdit ? 'Save' : 'Add',
                    variant: WfButtonVariant.primary,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WfNote(label.toUpperCase()),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: T.fillSoft,
            border: Border.all(color: T.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: T.ink3, fontSize: 13),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            style: const TextStyle(color: T.ink, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
