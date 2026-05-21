import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/sport_preset.dart';
import '../core/models/team.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/wf_button.dart';
import '../core/widgets/wf_card.dart';

/// Show the sport-preset form. Returns the entered draft, or null on cancel.
/// Pass `existing` to prefill for edit.
Future<SportPresetDraft?> showSportPresetFormSheet(
  BuildContext context, {
  SportPreset? existing,
}) {
  return showModalBottomSheet<SportPresetDraft>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PresetForm(existing: existing),
    ),
  );
}

class _PresetForm extends StatefulWidget {
  const _PresetForm({this.existing});
  final SportPreset? existing;

  @override
  State<_PresetForm> createState() => _PresetFormState();
}

class _PresetFormState extends State<_PresetForm> {
  late final TextEditingController _name;
  late final TextEditingController _periods;
  late final TextEditingController _periodMinutes;
  late String _sport;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _periods = TextEditingController(text: p == null ? '2' : '${p.numPeriods}');
    _periodMinutes = TextEditingController(
      text: p == null ? '20' : '${p.periodLengthMinutes}',
    );
    _sport = p?.sport ?? kSports.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _periods.dispose();
    _periodMinutes.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final periods = int.tryParse(_periods.text.trim());
    final minutes = int.tryParse(_periodMinutes.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (periods == null || periods < 1 || periods > 9) {
      setState(() => _error = 'Periods must be 1–9');
      return;
    }
    if (minutes == null || minutes < 1 || minutes > 120) {
      setState(() => _error = 'Period length must be 1–120 min');
      return;
    }
    Navigator.of(context).pop(
      SportPresetDraft(
        id: widget.existing?.id ?? '',
        name: name,
        sport: _sport,
        numPeriods: periods,
        periodLengthSeconds: minutes * 60,
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
              isEdit ? 'Edit sport setup' : 'New sport setup',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Name',
              controller: _name,
              hint: 'Soccer · Tournament A',
              autofocus: !isEdit,
            ),
            const SizedBox(height: 14),
            const WfNote('SPORT'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kSports
                  .map(
                    (s) => GestureDetector(
                      onTap: () => setState(() => _sport = s),
                      child: AnimatedContainer(
                        duration: T.fast,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _sport == s ? T.accent : T.fillSoft,
                          border: Border.all(
                            color: _sport == s ? T.accent : T.hair,
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _sport == s ? T.accentInk : T.ink2,
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
                Expanded(
                  child: _LabeledField(
                    label: 'Periods',
                    controller: _periods,
                    hint: '2',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LabeledField(
                    label: 'Period length (min)',
                    controller: _periodMinutes,
                    hint: '35',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
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
