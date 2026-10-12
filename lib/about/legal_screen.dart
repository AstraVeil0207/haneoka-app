import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// The privacy policy or terms of use (`legal.privacy`, `legal.terms`), as
/// the website's legal pages show them: title, effective date, summary and
/// numbered sections.
class LegalScreen extends StatelessWidget {
  const LegalScreen(this.document, {super.key});

  /// `privacy` or `terms`.
  final String document;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String k(String key) => t('legal.$document.$key');
    final sections = <(String, String)>[];
    for (var i = 0; k('sections.$i.title').isNotEmpty; i++) {
      sections.add((k('sections.$i.title'), k('sections.$i.body')));
    }
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(k('title'), style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                k('updated'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(k('summary'), style: body),
              for (final (index, (title, text)) in sections.indexed) ...[
                const SizedBox(height: 32),
                Text('${index + 1}. $title', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final paragraph in text.split('\n\n'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(paragraph, style: body),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
