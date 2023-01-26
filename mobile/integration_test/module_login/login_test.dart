import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/general_helper.dart';
import '../test_utils/login_helper.dart';

void main() async {
  await ImmichTestHelper.initialize();

  group("Login tests", () {
    immichWidgetTest("Test correct credentials", (tester, helper) async {
      await helper.loginHelper.waitForLoginScreen();
      await helper.loginHelper.acknowledgeNewServerVersion();
      await helper.loginHelper.enterCredentialsOf(
        LoginCredentials.testInstance,
      );
      await helper.loginHelper.pressLoginButton();
      await helper.loginHelper.assertLoginSuccess();
    });

    immichWidgetTest("Test login with wrong password", (tester, helper) async {
      await helper.loginHelper.waitForLoginScreen();
      await helper.loginHelper.acknowledgeNewServerVersion();
      await helper.loginHelper.enterCredentialsOf(
        LoginCredentials.testInstanceButWithWrongPassword,
      );
      await helper.loginHelper.pressLoginButton();
      await helper.loginHelper.assertLoginFailed();
    });

    immichWidgetTest("Test login with wrong server URL",
        (tester, helper) async {
      await helper.loginHelper.waitForLoginScreen();
      await helper.loginHelper.acknowledgeNewServerVersion();
      await helper.loginHelper.enterCredentialsOf(
        LoginCredentials.wrongInstanceUrl,
      );
      await helper.loginHelper.pressLoginButton();
      await helper.loginHelper.assertLoginFailed();
    });

    immichWidgetTest("Test sign out", (tester, helper) async {
      await helper.loginHelper.loginTo(LoginCredentials.testInstance);

      await helper.navigationHelper.openSideDrawer();
      await helper.navigationHelper.clickSignOutButton();

      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining("login_form_button_text".tr()),
        findsOneWidget,
      );
    });
  });
}
