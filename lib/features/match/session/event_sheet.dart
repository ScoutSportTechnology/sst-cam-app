// Event sheet — 2-step flow: event type → team + jersey.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';
import '../../teams/teams_state.dart' show teamsControllerProvider, Player;
import 'session_state.dart';

class EventSheet extends ConsumerStatefulWidget {
  const EventSheet({super.key, required this.homeTeamId, required this.onSave});
  final String homeTeamId;
  final void Function(String type, String team, String? jersey) onSave;

  @override
  ConsumerState<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<EventSheet> {
  static const _types = ['Goal', 'Foul', 'Card', 'Sub', 'Save', 'Other'];

  int _step = 0;
  String _type = '';
  String? _team;
  final _jersey = StringBuffer();
  String? _jerseyDropdownValue;
  bool _showNumberPad = false;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveMatchProvider);
    final allTeams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
    final homeTeam =
        allTeams.where((t) => t.id == widget.homeTeamId).firstOrNull;
    final homeRoster = homeTeam?.roster ?? const <Player>[];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: T.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: T.hair)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
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
            const SizedBox(height: 14),
            _StepHeader(step: _step, selectedType: _step == 1 ? _type : null),
            const SizedBox(height: 14),
            if (_step == 0) _typePicker() else _teamAndJersey(live, homeRoster),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: WfButton(
                    label: _step == 0 ? 'Cancel' : 'Back',
                    onPressed: _step == 0
                        ? () => Navigator.of(context).pop()
                        : () => setState(() => _step = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: _step == 0 ? 'Next' : 'Save event',
                    variant: WfButtonVariant.primary,
                    onPressed: _step == 0
                        ? (_type.isEmpty
                              ? null
                              : () => setState(() => _step = 1))
                        : (_team == null ||
                              (_jerseyDropdownValue == 'other' &&
                                  _jersey.isEmpty)
                          ? null
                          : () {
                              final jersey =
                                  (_jerseyDropdownValue != null &&
                                          _jerseyDropdownValue != 'other')
                                      ? _jerseyDropdownValue!
                                      : _jersey.toString();
                              widget.onSave(_type, _team!, jersey);
                              Navigator.of(context).pop();
                            }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What happened?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: T.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _types.map((t) {
            final on = t == _type;
            return GestureDetector(
              onTap: () => setState(() => _type = t),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: on ? T.accent : T.hair,
                    width: 1.4,
                  ),
                  color: on ? T.accentSoft : T.surface,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt_outlined, size: 18, color: T.ink),
                    const SizedBox(height: 4),
                    Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _teamAndJersey(LiveMatchState live, List<Player> homeRoster) {
    final isHomeSelected = _team == live.homeName;
    final activeRoster = isHomeSelected ? homeRoster : const <Player>[];
    final hasRoster = activeRoster.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Which team?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: T.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _teamCard('HOME', live.homeName, homeRoster)),
            const SizedBox(width: 8),
            Expanded(child: _teamCard('AWAY', live.awayName, const [])),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _team == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'Jersey #',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: T.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const WfNote('Optional'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (hasRoster) ...[
                      // Dropdown always visible when a roster exists.
                      // Selecting "Other…" adds the number pad below; picking
                      // a player back from the dropdown dismisses it.
                      Container(
                        height: 46,
                        decoration: BoxDecoration(
                          border: Border.all(color: T.hair),
                          color: T.surface,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _jerseyDropdownValue,
                            isExpanded: true,
                            dropdownColor: T.surface,
                            hint: const Text(
                              '—',
                              style: TextStyle(
                                fontFamily: T.mono,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: T.ink3,
                              ),
                            ),
                            icon: const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: T.ink2,
                            ),
                            style: const TextStyle(
                              fontFamily: T.mono,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: T.ink,
                            ),
                            items: [
                              for (final p in activeRoster)
                                DropdownMenuItem(
                                  value: p.number.toString(),
                                  child: Text('#${p.number}  ${p.name}'),
                                ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text(
                                  'Other…',
                                  style: TextStyle(
                                    fontFamily: T.mono,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: T.ink2,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _jerseyDropdownValue = v;
                              _showNumberPad = v == 'other';
                              if (v != 'other') _jersey.clear();
                            }),
                          ),
                        ),
                      ),
                      if (_showNumberPad) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: T.hair),
                            color: T.surface,
                          ),
                          child: Row(
                            children: [
                              Text(
                                _jersey.isEmpty ? '—' : _jersey.toString(),
                                style: const TextStyle(
                                  fontFamily: T.mono,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: T.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _NumberPad(
                          onTap: (k) {
                            setState(() {
                              if (k == '⌫') {
                                if (_jersey.isNotEmpty) {
                                  final s = _jersey.toString();
                                  _jersey
                                    ..clear()
                                    ..write(s.substring(0, s.length - 1));
                                }
                              } else if (k != '—' && _jersey.length < 3) {
                                _jersey.write(k);
                              }
                            });
                          },
                        ),
                      ],
                    ] else ...[
                      // No roster — number pad only.
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: T.hair),
                          color: T.surface,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _jersey.isEmpty ? '—' : _jersey.toString(),
                              style: const TextStyle(
                                fontFamily: T.mono,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: T.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _NumberPad(
                        onTap: (k) {
                          setState(() {
                            if (k == '⌫') {
                              if (_jersey.isNotEmpty) {
                                final s = _jersey.toString();
                                _jersey
                                  ..clear()
                                  ..write(s.substring(0, s.length - 1));
                              }
                            } else if (k != '—' && _jersey.length < 3) {
                              _jersey.write(k);
                            }
                          });
                        },
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _teamCard(String header, String name, List<Player> roster) {
    final on = _team == name;
    return GestureDetector(
      onTap: () => setState(() {
        _team = name;
        _jersey.clear();
        _jerseyDropdownValue = null;
        _showNumberPad = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: on ? T.accent : T.hair, width: 1.4),
          color: on ? T.accentSoft : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              header,
              style: const TextStyle(
                fontSize: 11,
                color: T.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STEP HEADER
// ---------------------------------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.selectedType});
  final int step;
  final String? selectedType;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Step ${step + 1} of 2',
          style: const TextStyle(fontSize: 12, color: T.ink2),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: T.rule, height: 1)),
        if (selectedType != null) ...[
          const SizedBox(width: 8),
          WfChip(label: selectedType!, active: true),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// NUMBER PAD
// ---------------------------------------------------------------------------

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '—', '0', '⌫'];
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      childAspectRatio: 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: keys.map((k) {
        return GestureDetector(
          onTap: () => onTap(k),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: T.hair),
              color: T.surface,
            ),
            alignment: Alignment.center,
            child: Text(
              k,
              style: TextStyle(
                fontFamily: T.mono,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: k == '—' ? T.ink3 : T.ink,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

