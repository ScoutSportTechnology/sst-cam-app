import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/team.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';

/// Show the create / edit team form. Returns the entered draft, or null if
/// the user cancelled. Pass `existing` to prefill for edit; the sheet keeps
/// `existing.id` on the returned draft so the controller routes to update.
Future<TeamDraft?> showTeamFormSheet(
  BuildContext context, {
  TeamRecord? existing,
}) {
  return showModalBottomSheet<TeamDraft>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _TeamForm(existing: existing),
    ),
  );
}

class _TeamForm extends StatefulWidget {
  const _TeamForm({this.existing});
  final TeamRecord? existing;

  @override
  State<_TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends State<_TeamForm> {
  late final TextEditingController _name;
  late final TextEditingController _shortName;
  late String _sport;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _shortName = TextEditingController(text: e?.shortName ?? '');
    _sport = e?.sport ?? kSports.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final shortName = _shortName.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Team name is required');
      return;
    }
    final resolvedShort = shortName.isEmpty ? _autoShort(name) : shortName;
    Navigator.of(context).pop(
      TeamDraft(
        id: widget.existing?.id ?? '',
        name: name,
        shortName: resolvedShort,
        sport: _sport,
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
              isEdit ? 'Edit team' : 'Add team',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Team name',
              controller: _name,
              hint: 'Northside Rovers U14',
              autofocus: true,
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: 'Short name (max 3)',
              controller: _shortName,
              hint: 'NRA',
              maxLength: kShortNameMaxLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kShortNameMaxLength),
                _UpperCaseFormatter(),
              ],
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
                    label: isEdit ? 'Save' : 'Create',
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
    this.maxLength,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final int? maxLength;
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
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: T.ink3, fontSize: 13),
              border: InputBorder.none,
              counterText: '',
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

String _autoShort(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = words.map((w) => w[0].toUpperCase()).join();
  return letters.length > kShortNameMaxLength
      ? letters.substring(0, kShortNameMaxLength)
      : letters;
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
