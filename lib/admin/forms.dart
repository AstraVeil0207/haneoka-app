import 'package:flutter/material.dart';

import '../chart_editor/project.dart';
import '../core/app_state.dart';
import '../ui/account_dialog.dart';

class AdminField {
  const AdminField(
    this.path,
    this.label, {
    this.options,
    this.number = false,
    this.toggle = false,
    this.multiline = false,
    this.required = false,
  });
  final String path, label;
  final Map<String, String>? options;
  final bool number, toggle, multiline, required;
}

Object? adminRead(Map row, String path) {
  Object? value = row;
  for (final key in path.split('.')) {
    value = value is Map ? value[key] : null;
  }
  return value;
}

void adminWrite(ChartMap row, String path, Object? value) {
  final parts = path.split('.');
  var at = row;
  for (final key in parts.take(parts.length - 1)) {
    at = chartMap(at[key] ??= <String, Object?>{});
  }
  at[parts.last] = value;
}

Future<void> editAdminFields(
  BuildContext context, {
  required String title,
  required ChartMap initial,
  required List<AdminField> fields,
  required Future<bool> Function(ChartMap) save,
  Future<ChartMap?> Function()? reload,
}) => showDialog<void>(
  context: context,
  builder: (_) => AccountDialog(
    child: _AdminForm(
      title: title,
      initial: initial,
      fields: fields,
      save: save,
      reload: reload,
    ),
  ),
);

class _AdminForm extends StatefulWidget {
  const _AdminForm({
    required this.title,
    required this.initial,
    required this.fields,
    required this.save,
    this.reload,
  });
  final String title;
  final ChartMap initial;
  final List<AdminField> fields;
  final Future<bool> Function(ChartMap) save;
  final Future<ChartMap?> Function()? reload;
  @override
  State<_AdminForm> createState() => _AdminFormState();
}

class _AdminFormState extends State<_AdminForm> {
  late ChartMap _draft = cloneChartMap(widget.initial);
  late final _texts = {
    for (final field in widget.fields)
      field.path: TextEditingController(
        text: '${adminRead(_draft, field.path) ?? ''}',
      ),
  };
  late final _focus = {
    for (final field in widget.fields) field.path: FocusNode(),
  };
  final _invalid = <String>{};
  bool _busy = false, _failed = false;
  Future<void> _save() async {
    _invalid.clear();
    final next = cloneChartMap(_draft);
    for (final field in widget.fields) {
      if (field.toggle || field.options != null) continue;
      final text = _texts[field.path]!.text.trim();
      if (field.required && text.isEmpty) {
        _invalid.add(field.path);
        continue;
      }
      if (field.number) {
        final value = num.tryParse(text);
        if (value == null || !value.isFinite) {
          _invalid.add(field.path);
        } else {
          adminWrite(next, field.path, value);
        }
      } else {
        adminWrite(next, field.path, text);
      }
    }
    if (_invalid.isNotEmpty) {
      setState(() {});
      _focus[_invalid.first]?.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    bool saved = false;
    try {
      saved = await widget.save(next);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    final value = await widget.reload?.call();
    if (!mounted) return;
    setState(() {
      if (value != null) {
        _draft = cloneChartMap(value);
        for (final field in widget.fields) {
          _texts[field.path]!.text = '${adminRead(_draft, field.path) ?? ''}';
        }
        _invalid.clear();
        _failed = false;
      }
      _busy = false;
    });
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          SizedBox.square(
            dimension: 24,
            child: _busy
                ? const CircularProgressIndicator(strokeWidth: 2)
                : _failed
                ? Tooltip(
                    message: t('admin.page.actions.failed'),
                    child: const Icon(Icons.error_outline),
                  )
                : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: field.toggle
                      ? SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(field.label),
                          value: adminRead(_draft, field.path) == true,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => adminWrite(_draft, field.path, v),
                                ),
                        )
                      : field.options != null
                      ? DropdownButtonFormField<String>(
                          key: ValueKey((
                            field.path,
                            adminRead(_draft, field.path),
                          )),
                          initialValue:
                              field.options!.containsKey(
                                '${adminRead(_draft, field.path)}',
                              )
                              ? '${adminRead(_draft, field.path)}'
                              : field.options!.keys.first,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: field.label),
                          items: [
                            for (final entry in field.options!.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => adminWrite(_draft, field.path, v),
                                ),
                        )
                      : TextField(
                          controller: _texts[field.path],
                          focusNode: _focus[field.path],
                          enabled: !_busy,
                          maxLines: field.multiline ? 4 : 1,
                          keyboardType: field.number
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : null,
                          decoration: InputDecoration(
                            labelText: field.label,
                            error: _invalid.contains(field.path)
                                ? const SizedBox.shrink()
                                : null,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.reload != null)
          TextButton(
            onPressed: _busy ? null : _reload,
            child: Text(t('admin.page.forum.reload')),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('common.actions.cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(t('admin.page.save')),
        ),
      ],
    );
  }
}
