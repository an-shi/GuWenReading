import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/reading_mode.dart';

class ReaderModeBar extends StatelessWidget {
  const ReaderModeBar({
    super.key,
    required this.mode,
    required this.side,
    required this.onModeChanged,
    required this.onSideChanged,
  });

  final ReaderMode mode;
  final IndependentSide side;
  final ValueChanged<ReaderMode> onModeChanged;
  final ValueChanged<IndependentSide> onSideChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in ReaderMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      selected: mode == value,
                      onSelected: (_) => onModeChanged(value),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon(value), size: 15),
                          const SizedBox(width: 5),
                          Text(
                            value.shortLabel,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (mode == ReaderMode.independent) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<IndependentSide>(
                    segments: const [
                      ButtonSegment(
                        value: IndependentSide.original,
                        label: Text('只看原文'),
                      ),
                      ButtonSegment(
                        value: IndependentSide.translation,
                        label: Text('只看译文'),
                      ),
                    ],
                    selected: {side},
                    onSelectionChanged: (value) => onSideChanged(value.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _icon(ReaderMode mode) => switch (mode) {
    ReaderMode.alternating => Icons.view_agenda_outlined,
    ReaderMode.originalFirst => Icons.article_outlined,
    ReaderMode.independent => Icons.swap_horiz_rounded,
    ReaderMode.sentence => Icons.format_list_bulleted_rounded,
    ReaderMode.columns => Icons.view_column_outlined,
  };
}

class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    super.key,
    required this.paragraph,
    required this.mode,
    required this.side,
    required this.fontSize,
    required this.lineHeight,
    required this.current,
    required this.onSentenceTap,
    required this.onParagraphTap,
  });

  final Paragraph paragraph;
  final ReaderMode mode;
  final IndependentSide side;
  final double fontSize;
  final double lineHeight;
  final bool current;
  final ValueChanged<Sentence> onSentenceTap;
  final VoidCallback onParagraphTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: current
            ? theme.colorScheme.primary.withValues(alpha: 0.025)
            : null,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.055),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${paragraph.ordinal + 1}',
              style: TextStyle(
                fontSize: 9.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.26),
              ),
            ),
          ),
          Expanded(
            child: switch (mode) {
              ReaderMode.alternating => _alternating(context),
              ReaderMode.originalFirst => GestureDetector(
                onTap: onParagraphTap,
                child: _original(context),
              ),
              ReaderMode.independent => GestureDetector(
                onTap: onParagraphTap,
                child: side == IndependentSide.original
                    ? _original(context)
                    : _translation(context),
              ),
              ReaderMode.sentence => _sentenceMode(context),
              ReaderMode.columns => _columns(context),
            },
          ),
        ],
      ),
    );
  }

  Widget _alternating(BuildContext context) {
    final theme = Theme.of(context);
    final hasTranslation = paragraph.sentences.any(
      (s) => s.translation != null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _original(context),
        const SizedBox(height: 12),
        if (hasTranslation)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.38),
                  width: 2,
                ),
              ),
            ),
            child: _translation(context),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _paragraphStateLabel(),
              style: TextStyle(
                fontSize: 10.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
      ],
    );
  }

  Widget _original(BuildContext context) {
    final theme = Theme.of(context);
    return _SentenceFlow(
      paragraph: paragraph,
      style: TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
      ),
      onTap: onSentenceTap,
    );
  }

  Widget _translation(BuildContext context) {
    final theme = Theme.of(context);
    return _SentenceFlow(
      paragraph: paragraph,
      translated: true,
      style: TextStyle(
        fontSize: fontSize * 0.88,
        height: lineHeight,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
      ),
      placeholderStyle: TextStyle(
        fontSize: fontSize * 0.7,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.33),
      ),
      manualMarkSize: fontSize * 0.5,
      onTap: onSentenceTap,
    );
  }

  Widget _columns(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _original(context)),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
        ),
        Expanded(child: _translation(context)),
      ],
    );
  }

  Widget _sentenceMode(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final sentence in paragraph.sentences)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => onSentenceTap(sentence),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sentence.originalText,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: lineHeight,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (sentence.translation != null)
                    Text(
                      sentence.translation!.text,
                      style: TextStyle(
                        fontSize: fontSize * 0.88,
                        height: lineHeight,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.66,
                        ),
                      ),
                    )
                  else
                    Text(
                      '〔${stateLabel(sentence.state)}〕',
                      style: TextStyle(
                        fontSize: fontSize * 0.72,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.33,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _paragraphStateLabel() {
    final states = paragraph.sentences.map((s) => s.state).toSet();
    if (states.contains('translating')) return '本段正在翻译…';
    if (states.contains('queued')) return '本段译文排队中…';
    if (states.contains('failed')) return '本段翻译失败';
    return '本段尚未翻译';
  }
}

/// Renders a paragraph as one continuous flowing text while keeping every
/// sentence individually tappable. This is how Chinese paragraphs should wrap.
class _SentenceFlow extends StatefulWidget {
  const _SentenceFlow({
    required this.paragraph,
    required this.style,
    required this.onTap,
    this.translated = false,
    this.placeholderStyle,
    this.manualMarkSize = 10,
  });

  final Paragraph paragraph;
  final TextStyle style;
  final TextStyle? placeholderStyle;
  final double manualMarkSize;
  final bool translated;
  final ValueChanged<Sentence> onTap;

  @override
  State<_SentenceFlow> createState() => _SentenceFlowState();
}

class _SentenceFlowState extends State<_SentenceFlow> {
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void didUpdateWidget(covariant _SentenceFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final valid = widget.paragraph.sentences.map((s) => s.id).toSet();
    final stale = _recognizers.keys.where((id) => !valid.contains(id)).toList();
    for (final id in stale) {
      _recognizers.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(Sentence sentence) {
    return _recognizers.putIfAbsent(sentence.id, () {
      return TapGestureRecognizer()
        ..onTap = () {
          final current = widget.paragraph.sentences.firstWhere(
            (item) => item.id == sentence.id,
            orElse: () => sentence,
          );
          widget.onTap(current);
        };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    for (final sentence in widget.paragraph.sentences) {
      final recognizer = _recognizer(sentence);
      if (!widget.translated) {
        spans.add(
          TextSpan(
            text: sentence.originalText,
            recognizer: recognizer,
            style: sentence.needsReview
                ? widget.style.copyWith(
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    decorationColor: theme.colorScheme.secondary.withValues(
                      alpha: 0.4,
                    ),
                  )
                : widget.style,
          ),
        );
      } else if (sentence.translation != null) {
        spans.add(
          TextSpan(
            text: sentence.translation!.text,
            recognizer: recognizer,
            style: widget.style,
          ),
        );
        if (sentence.isManual) {
          spans.add(
            TextSpan(
              text: ' 人',
              style: TextStyle(
                fontSize: widget.manualMarkSize,
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      } else {
        spans.add(
          TextSpan(
            text: '〔${stateLabel(sentence.state)}〕',
            recognizer: recognizer,
            style: widget.placeholderStyle,
          ),
        );
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
