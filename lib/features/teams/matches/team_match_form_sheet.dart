import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/sport_presets/sport_presets_state.dart'
    show sportPresetsForSportProvider, SportPreset;
import '../teams_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';

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
  final _opponentCustom = TextEditingController();
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

  // Opponent selection. `_opponentTeam` is the picked team from the
  // dropdown; null + `_useCustomOpponent` = manual entry (one-off team
  // not in the roster).
  TeamRecord? _opponentTeam;
  bool _useCustomOpponent = false;

  @override
  void dispose() {
    _opponentCustom.dispose();
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
    final opponent = _useCustomOpponent
        ? _opponentCustom.text.trim()
        : (_opponentTeam?.name ?? '');
    if (opponent.isEmpty) {
      setState(
        () => _error = _useCustomOpponent
            ? 'Opponent name is required'
            : 'Pick an opponent team',
      );
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
    // Store the bare opponent name (e.g. "Eastfield FC"), never "vs Eastfield
    // FC". The "vs " is a display concern; views add it where they want it.
    final opp = opponent.startsWith('vs ') ? opponent.substring(3) : opponent;
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
    final allTeams =
        ref.watch(teamsControllerProvider).valueOrNull ?? const <TeamRecord>[];
    // Opponent options: visible teams matching the home team's sport,
    // excluding the home team itself.
    final opponents = allTeams
        .where(
          (t) =>
              !t.hidden &&
              t.id != widget.team.id &&
              t.sport == widget.team.sport,
        )
        .toList();
    if (!_initialized) {
      if (presets.isNotEmpty) _preset = presets.first;
      if (opponents.isNotEmpty) _opponentTeam = opponents.first;
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
            _OpponentPicker(
              teams: opponents,
              homeSport: widget.team.sport,
              selected: _opponentTeam,
              useCustom: _useCustomOpponent,
              customController: _opponentCustom,
              onPickTeam: (t) => setState(() {
                _opponentTeam = t;
                _useCustomOpponent = false;
              }),
              onPickCustom: () => setState(() {
                _useCustomOpponent = true;
                _opponentTeam = null;
              }),
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
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
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

/// Opponent input. Defaults to a dropdown of teams matching the home
/// team's sport, with a small "Other (manual)" escape hatch for one-off
/// opponents not in the roster.
class _OpponentPicker extends StatelessWidget {
  const _OpponentPicker({
    required this.teams,
    required this.homeSport,
    required this.selected,
    required this.useCustom,
    required this.customController,
    required this.onPickTeam,
    required this.onPickCustom,
  });

  final List<TeamRecord> teams;
  final String homeSport;
  final TeamRecord? selected;
  final bool useCustom;
  final TextEditingController customController;
  final ValueChanged<TeamRecord> onPickTeam;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WfNote('OPPONENT'),
        const SizedBox(height: 6),
        if (teams.isEmpty && !useCustom) ...[
          Container(
            decoration: BoxDecoration(
              color: T.fillSoft,
              border: Border.all(color: T.hair),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Text(
              'No other $homeSport teams on the camera. Add one in the '
              'Teams tab, or pick "Other" below.',
              style: const TextStyle(color: T.ink2, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 6),
        ] else if (!useCustom) ...[
          Container(
            decoration: BoxDecoration(
              color: T.fillSoft,
              border: Border.all(color: T.hair),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TeamRecord>(
                value: selected,
                isExpanded: true,
                isDense: true,
                dropdownColor: T.surface,
                style: const TextStyle(fontSize: 13, color: T.ink),
                icon: const Icon(Icons.expand_more, size: 16, color: T.ink2),
                items: [
                  for (final t in teams)
                    DropdownMenuItem(value: t, child: Text(t.name)),
                ],
                onChanged: (v) {
                  if (v != null) onPickTeam(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            GestureDetector(
              onTap: onPickCustom,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  useCustom ? '✓ Other (custom name)' : 'Other (custom name)',
                  style: TextStyle(
                    fontSize: 12,
                    color: useCustom ? T.accent : T.ink2,
                    fontWeight: useCustom ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (useCustom) ...[
          Container(
            decoration: BoxDecoration(
              color: T.fillSoft,
              border: Border.all(color: T.hair),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: customController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Eastfield FC',
                hintStyle: TextStyle(color: T.ink3, fontSize: 13),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(color: T.ink, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}
