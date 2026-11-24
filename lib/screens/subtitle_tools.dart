import 'package:flutter/material.dart';

import '../services/api.dart';
import '../widgets/common.dart';

enum SubtitleTool {
  preview('Preview'),
  sync('Sync', action: 'sync'),
  removeHi('Remove HI tags', action: 'remove_HI'),
  removeStyle('Remove style tags', action: 'remove_tags'),
  removeEmoji('Remove emoji', action: 'emoji'),
  ocr('OCR fixes', action: 'OCR_fixes'),
  common('Common fixes', action: 'common'),
  uppercase('Fix uppercase', action: 'fix_uppercase'),
  rtl('Reverse RTL', action: 'reverse_rtl'),
  color('Add color'),
  frameRate('Change frame rate'),
  offset('Adjust times'),
  fit('Two-point fit'),
  translate('Translate', action: 'translate'),
  extract('Extract', action: 'extract'),
  delete('Delete');

  const SubtitleTool(this.label, {this.action});
  final String label;
  final String? action;
}

typedef SubtitleToolRequest = ({String action, Map<String, String> options});

String subtitleFileName(String path) => path.split(RegExp(r'[/\\]')).last;

class SubtitleToolDialog extends StatefulWidget {
  const SubtitleToolDialog({
    super.key,
    required this.tool,
    required this.api,
    required this.media,
    required this.subtitle,
  });

  final SubtitleTool tool;
  final BazarrApi api;
  final MediaRef media;
  final Json subtitle;

  @override
  State<SubtitleToolDialog> createState() => _SubtitleToolDialogState();
}

class _SubtitleToolDialogState extends State<SubtitleToolDialog> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _syncOptions = <String, String>{};
  late Future<Json>? _data;
  Json? _firstCue;
  Json? _lastCue;
  String? _selection;
  String? _error;
  bool _noFixFramerate = false;
  bool _goldenSection = false;
  bool _preserveFormat = true;

  SubtitleTool get tool => widget.tool;
  String get path => widget.subtitle['path'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    if (tool == SubtitleTool.offset) _first.text = '0';
    _data = _load();
  }

  Future<Json>? _load() => switch (tool) {
    SubtitleTool.sync => widget.api.subtitleReferences(widget.media, path),
    SubtitleTool.fit => _loadFit(),
    SubtitleTool.translate => _loadTranslation(),
    _ => null,
  };

  Future<Json> _loadFit() async {
    final cues = await widget.api.subtitleContents(path);
    if (mounted && cues.length >= 2) {
      final inset = cues.length < 50 ? 0 : 9;
      _selectCue(cues[inset], first: true);
      _selectCue(cues[cues.length - 1 - inset], first: false);
    }
    return {'cues': cues};
  }

  Future<Json> _loadTranslation() async {
    final languages = await widget.api.enabledLanguages();
    Json translator;
    try {
      translator = await widget.api.subtitleTranslator();
    } on ApiException {
      translator = const {};
    }
    return {
      'languages': [
        for (final language in languages)
          if (translator['type'] != 'google_translate' ||
              _googleLanguages.contains(language['code2']))
            language,
      ],
      'translator': switch ((translator['type'], translator['model'])) {
        ('google_translate', _) => 'Google Translate',
        ('gemini', final String model) when model.isNotEmpty =>
          'Gemini ($model)',
        ('gemini', _) => 'Gemini',
        ('lingarr', _) => 'Lingarr',
        _ => 'your server’s configured translation service',
      },
    };
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _data,
    builder: (context, snapshot) {
      final waiting =
          _data != null && snapshot.connectionState != ConnectionState.done;
      final data = snapshot.data ?? const <String, dynamic>{};
      final error = waiting ? null : snapshot.error;
      // Sync can use the server's automatic reference when track discovery fails.
      final showFields =
          !waiting && (error == null || tool == SubtitleTool.sync);
      final canSubmit =
          showFields &&
          switch (tool) {
            SubtitleTool.fit => _firstCue != null && _lastCue != null,
            SubtitleTool.translate => jsonList(data['languages']).isNotEmpty,
            _ => true,
          };
      return AlertDialog(
        title: Text(tool == SubtitleTool.sync ? 'Sync subtitle' : tool.label),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            child: waiting
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null) ...[
                        Text('Could not load options. $error'),
                        TextButton(
                          onPressed: () => setState(() => _data = _load()),
                          child: const Text('Retry'),
                        ),
                      ],
                      if (showFields) ..._fields(data),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: Text(tool == SubtitleTool.sync ? 'Sync' : 'Apply'),
          ),
        ],
      );
    },
  );

  List<Widget> _fields(Json data) => switch (tool) {
    SubtitleTool.sync => _syncFields(data),
    SubtitleTool.color => [
      _choice('Color', _colors, (value) => _selection = value, required: true),
    ],
    SubtitleTool.frameRate => [
      _number('Original frame rate (fps)', _first, positive: true),
      _number('Target frame rate (fps)', _last, positive: true),
    ],
    SubtitleTool.offset => [
      const Text(
        'Use a positive offset to delay subtitles or a negative offset to show them earlier.',
      ),
      _number('Offset (seconds)', _first, signed: true),
    ],
    SubtitleTool.fit => _fitFields(jsonList(data['cues'])),
    SubtitleTool.translate => [
      Text('Bazarr will use ${data['translator']}.'),
      if (jsonList(data['languages']).isEmpty)
        const Text(
          'No supported translation languages are enabled on this server.',
        ),
      _choice(
        'Target language',
        {
          for (final language in jsonList(data['languages']))
            if (language['code2'] case final String code when code.isNotEmpty)
              code: '${language['name'] ?? code}',
        },
        (value) => _selection = value,
        required: true,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Preserve original format'),
        value: _preserveFormat,
        onChanged: (value) => setState(() => _preserveFormat = value),
      ),
    ],
    _ => const [],
  };

  List<Widget> _syncFields(Json data) {
    final references = <String, String>{};
    for (final (key, prefix) in [
      ('audio_tracks', 'Audio'),
      ('embedded_subtitles_tracks', 'Embedded subtitle'),
      ('external_subtitles_tracks', 'External subtitle'),
    ]) {
      for (final track in jsonList(data[key])) {
        final reference =
            track[key == 'external_subtitles_tracks' ? 'path' : 'stream'];
        if (reference is! String || reference.isEmpty || reference == path) {
          continue;
        }
        final name = [track['name'], track['language']]
            .whereType<String>()
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => subtitleFileName(reference),
            );
        references[reference] = key == 'external_subtitles_tracks'
            ? '$prefix · $name'
            : '$prefix · $name ($reference)';
      }
    }
    return [
      _syncChoice(
        'Reference',
        'reference',
        references,
        defaultLabel: 'Automatic',
      ),
      _syncChoice(
        'Maximum offset (seconds)',
        'max_offset_seconds',
        _numbers([60, 120, 300, 600]),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('No framerate correction'),
        value: _noFixFramerate,
        onChanged: (value) => setState(() => _noFixFramerate = value!),
      ),
      if (!_noFixFramerate) ...[
        const Text('Framerate correction quality checks'),
        _syncChoice(
          'Minimum quality score',
          'quality_min_score',
          _numbers([for (var i = 0; i <= 10; i++) i / 10]),
        ),
        _syncChoice(
          'Quality maximum offset (seconds)',
          'quality_max_offset_seconds',
          _numbers([5, 10, 15, 20, 30, 45, 60]),
        ),
        _syncChoice(
          'Maximum framerate deviation',
          'quality_max_framerate_deviation',
          _numbers([0.05, 0.1, 0.15, 0.2, 0.3]),
        ),
      ],
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Golden-section search'),
        value: _goldenSection,
        onChanged: (value) => setState(() => _goldenSection = value!),
      ),
    ];
  }

  Map<String, String> _numbers(List<num> values) => {
    for (final value in values) '$value': '$value',
  };

  Widget _syncChoice(
    String label,
    String key,
    Map<String, String> values, {
    String defaultLabel = 'Server default',
  }) => _choice(label, {'': defaultLabel, ...values}, (value) {
    if (value == null || value.isEmpty) {
      _syncOptions.remove(key);
    } else {
      _syncOptions[key] = value;
    }
  }, initial: _syncOptions[key] ?? '');

  Widget _choice(
    String label,
    Map<String, String> values,
    ValueChanged<String?> onChanged, {
    String? initial,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey(label),
      initialValue: values.containsKey(initial) ? initial : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in values.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: values.isEmpty ? null : onChanged,
      validator: required
          ? (value) => value == null ? 'Select an option' : null
          : null,
    ),
  );

  Widget _number(
    String label,
    TextEditingController controller, {
    bool positive = false,
    bool signed = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      validator: (_) {
        final value = _parseNumber(controller.text);
        if (value == null || !value.isFinite) return 'Enter a number';
        if (positive && value <= 0) return 'Enter a number greater than zero';
        if (signed && (_milliseconds(value) ?? 0) == 0) {
          return 'Enter a valid offset of at least one millisecond';
        }
        return null;
      },
    ),
  );

  List<Widget> _fitFields(List<Json> cues) {
    if (cues.length < 2) {
      return [const Text('Two-point fit requires at least two subtitle cues.')];
    }
    return [
      const Text(
        'Choose two cues and enter when each should start in the video.',
      ),
      _cueField(cues, first: true),
      _cueField(cues, first: false),
    ];
  }

  Widget _cueField(List<Json> cues, {required bool first}) {
    final selected = first ? _firstCue : _lastCue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: () async {
            final cue = await Navigator.push<Json>(
              context,
              MaterialPageRoute(
                builder: (_) => SubtitleCueScreen(
                  title: first ? 'Choose first cue' : 'Choose last cue',
                  load: () async => cues,
                  pick: true,
                ),
              ),
            );
            if (mounted && cue != null) {
              setState(() {
                _error = null;
                _selectCue(cue, first: first);
              });
            }
          },
          child: Text(
            selected == null
                ? (first ? 'Choose first cue' : 'Choose last cue')
                : _cueLabel(selected),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextFormField(
          controller: first ? _first : _last,
          decoration: InputDecoration(
            labelText: first ? 'First cue target time' : 'Last cue target time',
            hintText: 'HH:MM:SS.mmm',
          ),
          keyboardType: TextInputType.datetime,
          validator: (text) => _parseTime(text ?? '') == null
              ? 'Use HH:MM:SS.mmm or seconds'
              : null,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _selectCue(Json cue, {required bool first}) {
    final time = _formatTime(_cueTime(cue['start']));
    if (first) {
      _firstCue = cue;
      _first.text = time;
    } else {
      _lastCue = cue;
      _last.text = time;
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final options = <String, String>{};
    final String action;
    switch (tool) {
      case SubtitleTool.sync:
        action = 'sync';
        options.addAll(_syncOptions);
        if (_noFixFramerate) {
          options.removeWhere((key, _) => key.startsWith('quality_'));
        }
        options['no_fix_framerate'] = _pythonBool(_noFixFramerate);
        options['gss'] = _pythonBool(_goldenSection);
      case SubtitleTool.color:
        action = 'color(name=$_selection)';
      case SubtitleTool.frameRate:
        action =
            'change_FPS(from=${_parseNumber(_first.text)},to=${_parseNumber(_last.text)})';
      case SubtitleTool.offset:
        final milliseconds = _milliseconds(_parseNumber(_first.text)!)!;
        action = 'shift_offset(h=0,m=0,s=0,ms=$milliseconds)';
      case SubtitleTool.fit:
        if (_firstCue == null || _lastCue == null) return;
        final sourceFirst = _cueTime(_firstCue!['start']);
        final sourceLast = _cueTime(_lastCue!['start']);
        final targetFirst = _parseTime(_first.text)!;
        final targetLast = _parseTime(_last.text)!;
        if (sourceLast <= sourceFirst || targetLast <= targetFirst) {
          setState(
            () => _error =
                'The last cue must follow the first in both sets of times.',
          );
          return;
        }
        action =
            'two_point_fit(rh=0,rm=0,rs=0,rms=$sourceFirst,'
            'oh=0,om=0,os=0,oms=$targetFirst,'
            'from=${targetLast - targetFirst},to=${sourceLast - sourceFirst})';
      case SubtitleTool.translate:
        action = 'translate';
        options['language'] = _selection!;
        options['original_format'] = _pythonBool(_preserveFormat);
      default:
        return;
    }
    Navigator.pop(context, (action: action, options: options));
  }
}

class SubtitleCueScreen extends StatefulWidget {
  const SubtitleCueScreen({
    super.key,
    required this.title,
    required this.load,
    this.pick = false,
  });

  final String title;
  final Future<List<Json>> Function() load;
  final bool pick;

  @override
  State<SubtitleCueScreen> createState() => _SubtitleCueScreenState();
}

class _SubtitleCueScreenState extends State<SubtitleCueScreen> {
  late Future<List<Json>> _cues = widget.load();
  String _filter = '';
  bool _raw = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<List<Json>>(
      future: _cues,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorView(
            error: snapshot.error!,
            onRetry: () => setState(() => _cues = widget.load()),
          );
        }
        final cues = snapshot.data!;
        final matches = _filter.isEmpty
            ? cues
            : cues
                  .where(
                    (cue) => _cueLabel(cue).toLowerCase().contains(_filter),
                  )
                  .toList();
        return Column(
          children: [
            if (!widget.pick && cues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Rendered')),
                    ButtonSegment(value: true, label: Text('Raw')),
                  ],
                  selected: {_raw},
                  onSelectionChanged: (value) =>
                      setState(() => _raw = value.single),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search subtitle cues',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _filter = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        cues.isEmpty
                            ? 'No subtitle cues found'
                            : 'No matching cues',
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final cue = matches[index];
                        final content = '${cue['content'] ?? ''}';
                        return ListTile(
                          title: _raw
                              ? Text(content)
                              : Text.rich(_renderCue(content)),
                          subtitle: Text(
                            '#${cue['index']} · ${_formatTime(_cueTime(cue['start']))}'
                            ' – ${_formatTime(_cueTime(cue['end']))}',
                          ),
                          onTap: widget.pick
                              ? () => Navigator.pop(context, cue)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

// Interpret subtitle formatting as Flutter text spans. Subtitle text never runs
// in a browser, and tags cannot load resources or attach interactive behavior.
TextSpan _renderCue(String content) {
  final spans = <TextSpan>[];
  final styles = <String>{};
  final colors = <Color?>[];
  var cursor = 0;

  void addText(String text) {
    if (text.isEmpty) return;
    spans.add(
      TextSpan(
        text: text.replaceAllMapped(
          _cueEntity,
          (match) => switch (match[0]) {
            '&amp;' => '&',
            '&lt;' => '<',
            '&gt;' => '>',
            '&quot;' => '"',
            '&apos;' => "'",
            _ => '\u00a0',
          },
        ),
        style: TextStyle(
          fontWeight: styles.contains('b') ? FontWeight.bold : null,
          fontStyle: styles.contains('i') ? FontStyle.italic : null,
          color: colors.lastOrNull,
          decoration: TextDecoration.combine([
            if (styles.contains('u')) TextDecoration.underline,
            if (styles.contains('s')) TextDecoration.lineThrough,
          ]),
        ),
      ),
    );
  }

  for (final token in _cueMarkup.allMatches(content)) {
    addText(content.substring(cursor, token.start));
    cursor = token.end;
    final value = token[0]!;
    final tag = token[2]?.toLowerCase();
    if (tag != null) {
      final closing = token[1] == '/';
      switch (tag) {
        case 'br':
          addText('\n');
        case 'font':
          if (closing) {
            if (colors.isNotEmpty) colors.removeLast();
          } else {
            final hex = _cueColor.firstMatch(value)?[1];
            colors.add(
              hex == null
                  ? colors.lastOrNull
                  : Color(0xff000000 | int.parse(hex, radix: 16)),
            );
          }
        default:
          final style = switch (tag) {
            'em' => 'i',
            'strong' => 'b',
            _ => tag,
          };
          closing ? styles.remove(style) : styles.add(style);
      }
    } else if (value.startsWith('{')) {
      for (final flag in _assFlag.allMatches(value)) {
        flag[2] == '1' ? styles.add(flag[1]!) : styles.remove(flag[1]!);
      }
    } else {
      addText(value == r'\h' ? ' ' : '\n');
    }
  }
  addText(content.substring(cursor));
  return TextSpan(children: spans);
}

final _cueMarkup = RegExp(
  r'''<(/?)(i|b|u|s|em|strong|font|br)\b[^>]*>|\{\\[^}]*\}|\\[Nnh]''',
  caseSensitive: false,
);
final _cueColor = RegExp(
  r'''\bcolor\s*=\s*["']?#([a-f0-9]{6})\b''',
  caseSensitive: false,
);
final _cueEntity = RegExp(r'&(amp|lt|gt|quot|apos|nbsp);');
final _assFlag = RegExp(r'\\([ibus])([01])(?!\d)');

String _cueLabel(Json cue) =>
    '#${cue['index']} · ${_formatTime(_cueTime(cue['start']))}'
    ' · ${cue['content'] ?? ''}';

int _cueTime(Object? value) {
  if (value is! Map) return 0;
  return ((value['total_seconds'] as num?)?.toInt() ?? 0) * 1000 +
      ((value['microseconds'] as num?)?.toInt() ?? 0) ~/ 1000;
}

String _formatTime(int milliseconds) {
  final time = Duration(milliseconds: milliseconds.abs());
  final sign = milliseconds < 0 ? '-' : '';
  String pad(int value, int digits) => value.toString().padLeft(digits, '0');
  return '$sign${pad(time.inHours, 2)}:${pad(time.inMinutes.remainder(60), 2)}:'
      '${pad(time.inSeconds.remainder(60), 2)}.${pad(time.inMilliseconds.remainder(1000), 3)}';
}

double? _parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

int? _parseTime(String text) {
  final parts = text.trim().split(':');
  final seconds = _parseNumber(parts.last);
  if (seconds == null || !seconds.isFinite || seconds < 0) return null;
  if (parts.length == 1) return _milliseconds(seconds);
  if (parts.length != 3 || seconds >= 60) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null ||
      hours < 0 ||
      minutes == null ||
      minutes < 0 ||
      minutes >= 60) {
    return null;
  }
  return _milliseconds(hours * 3600.0 + minutes * 60 + seconds);
}

int? _milliseconds(double seconds) {
  final value = seconds * 1000;
  // Keep millisecond values within the range that a double represents exactly.
  return value.abs() <= 9007199254740991 ? value.round() : null;
}

String _pythonBool(bool value) => value ? 'True' : 'False';

const _colors = {
  'white': 'White',
  'light-grey': 'Light gray',
  'red': 'Red',
  'green': 'Green',
  'yellow': 'Yellow',
  'blue': 'Blue',
  'magenta': 'Magenta',
  'cyan': 'Cyan',
  'black': 'Black',
  'dark-red': 'Dark red',
  'dark-green': 'Dark green',
  'dark-yellow': 'Dark yellow',
  'dark-blue': 'Dark blue',
  'dark-magenta': 'Dark magenta',
  'dark-cyan': 'Dark cyan',
  'dark-grey': 'Dark gray',
};

// Matches the languages offered by Bazarr's Google Translate dialog.
final _googleLanguages =
    '''
af sq am ar hy az eu be bn bs bg ca ceb ny zh zt
co hr cs da nl en eo et tl fi fr fy gl ka de el
gu ht ha haw iw hi hmn hu is ig id ga it ja jw kn
kk km ko ku ky lo la lv lt lb mk mg ms ml mt mi
mr mn my ne no ps fa pl pt pa ro ru sm gd sr st
sn sd si sk sl so es su sw sv tg ta te th tr uk
ur uz vi cy xh yi yo zu fil he
'''
        .trim()
        .split(RegExp(r'\s+'))
        .toSet();
