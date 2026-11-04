import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppTheme configuration smoke test', () {
    final theme = AppTheme.cinemaDark;
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.primaryColor, AppColors.primary);
  });
}
