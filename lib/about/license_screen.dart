import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool _registeredChartLicenses = false;
void registerChartEditorLicenses() {
  if (_registeredChartLicenses) return;
  _registeredChartLicenses = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Haneoka',
    ], await rootBundle.loadString('LICENSE'));
    for (final file in [
      'LICENSE.next-sekai.txt',
      'LICENSE.next-sekai-editor.txt',
      'LICENSE.sekai.txt',
    ]) {
      yield LicenseEntryWithLineBreaks([
        'Haneoka Chart Editor',
        'Next-SEKAI',
      ], await rootBundle.loadString('third_party/chart_editor/$file'));
    }
  });
}

class AppLicenseScreen extends StatelessWidget {
  const AppLicenseScreen({super.key});
  @override
  Widget build(BuildContext context) {
    registerChartEditorLicenses();
    return const LicensePage(
      applicationName: 'Haneoka',
      applicationLegalese: 'MPL-2.0',
    );
  }
}
