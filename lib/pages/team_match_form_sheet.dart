import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';

/// Show the add-match form. Returns the entered draft, or null on cancel.
/// User picks `Past match` (only counts toward stats) or `Upcoming match`
/// (counts toward stats AND will be recorded / streamed).
///
/// `team` provides the base sport used to filter sport-setup options for
/// upcoming matches.
Future<TeamMatchDraft?> showTeamMatchFormSheet(
  BuildContext context, {
  required TeamRecord team,
}) {
  return showModalBottomSheet<TeamMatchDraft>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _MatchForm(team: team),
    ),
  );
}

class _MatchForm extends ConsumerStatefulWidget {
  const _MatchForm({required this.team});
  final TeamRecord team;

  @override
  ConsumerState<_MatchForm> createState() => _MatchFormState();
}

class _MatchFormState extends ConsumerState<_MatchForm> {
  final _opponent = TextEditingController();
  final _scoreFor = TextEditingController();
  final _scoreAgainst = TextEditingController();
  final _customPeriods = TextEditingController(text: '2');
  final _customMinutes = TextEditingController(text: '20');
  DateTime _date = DateTime.now();
  MatchKind _kind = MatchKind.upcoming;
  // null => "Custom" (read time config from the two text controllers).
  SportPreset? _preset;
  bool _initialized = false;
  String? _error;

  @override
  void dispose() {
    _opponent.dispose();
    _scoreFor.dispose();
    _scoreAgainst.dispose();
    _customPeriods.dispose();
    _customMinutes.dispose();
    super.dispose();
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final opponent = _opponent.text.trim();
    if (opponent.isEmpty) {
      setState(() => _error = 'Opponent is required');
      return;
    }
    var result = '';
    var numPeriods = 0;
    var periodLengthSeconds = 0;
    if (_kind == MatchKind.past) {
      final sf = int.tryParse(_scoreFor.text.trim());
      final sa = int.tryParse(_scoreAgainst.text.trim());
      if (sf == null || sa == null || sf < 0 || sa < 0) {
        setState(() => _error = 'Enter both scores for a past match');
        return;
      }
      final outcome = sf > sa ? 'W' : (sf < sa ? 'L' : 'D');
      result = '$outcome $sf–$sa';
    } else {
      // Upcoming → require time config (preset or custom).
      if (_preset != null) {
        numPeriods = _preset!.numPeriods;
        periodLengthSeconds = _preset!.periodLengthSeconds;
      } else {
        final p = int.tryParse(_customPeriods.text.trim());
        final m = int.tryParse(_customMinutes.text.trim());
        if (p == null || p < 1 || p > 9) {
          setState(() => _error = 'Periods must be 1–9');
          return;
        }
        if (m == null || m < 1 || m > 120) {
          setState(() => _error = 'Period length must be 1–120 min');
          return;
        }
        numPeriods = p;
        periodLengthSeconds = m * 60;
      }
    }
    final opp = opponent.startsWith('vs ') ? opponent : 'vs $opponent';
    Navigator.of(context).pop(
      TeamMatchDraft(
        opponent: opp,
        date: _formatDate(_date),
        kind: _kind,
        result: result,
        numPeriods: numPeriods,
        periodLengthSeconds: periodLengthSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(sportPresetsForSportProvider(widget.team.sport));
    if (!_initialized && presets.isNotEmpty) {
      _preset = presets.first;
      _initialized = true;
    }

    return SafeArea(
      child: SingleChildScrollView(
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
            const Text(
              'Add match',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.team.name} · ${widget.team.sport}',
              style: const TextStyle(fontSize: 12, color: T.ink2),
            ),
            const SizedBox(height: 14),
            _KindToggle(
              kind: _kind,
              onChanged: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Opponent',
              controller: _opponent,
              hint: 'Eastfield FC',
              autofocus: true,
            ),
            const SizedBox(height: 10),
            _DatePickerRow(label: _formatDate(_date), onTap: _pickDate),
            if (_kind == MatchKind.past) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _LabeledField(
                      label: 'Goals for',
                      controller: _scoreFor,
                      hint: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LabeledField(
                      label: 'Goals against',
                      controller: _scoreAgainst,
                      hint: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              const WfNote('SPORT SETUP'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in presets)
                    GestureDetector(
                      onTap: () => setState(() => _preset = p),
                      child: WfChip(
                        label: '${p.name} · ${p.summary}',
                        active: _preset?.id == p.id,
                      ),
                    ),
                  GestureDetector(
                    onTap: () => setState(() => _preset = null),
                    child: WfChip(label: 'Custom…', active: _preset == null),
                  ),
                ],
              ),
              if (_preset == null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'Periods',
                        controller: _customPeriods,
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
                        controller: _customMinutes,
                        hint: '20',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
                    label: 'Add',
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

class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.kind, required this.onChanged});
  final MatchKind kind;
  final ValueChanged<MatchKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _kindCard(
            'Upcoming',
            'Stats + record / stream',
            on: kind == MatchKind.upcoming,
            onTap: () => onChanged(MatchKind.upcoming),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kindCard(
            'Past match',
            'Counts toward stats only',
            on: kind == MatchKind.past,
            onTap: () => onChanged(MatchKind.past),
          ),
        ),
      ],
    );
  }

  Widget _kindCard(
    String title,
    String sub, {
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: on ? T.accent : T.hair, width: 1.4),
          color: on ? T.accentSoft : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? T.accent : T.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 11, color: T.ink2)),
          ],
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WfNote('DATE'),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: T.fillSoft,
              border: Border.all(color: T.hair),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: T.ink, fontSize: 13),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: T.ink2,
                ),
              ],
            ),
          ),
        ),
      ],
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
