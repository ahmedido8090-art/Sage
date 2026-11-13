// widgets/sage_screen_header.dart
//
// The header for pushed screens: a 48dp back target and a title that shrinks
// gracefully instead of overflowing on narrow screens or with large text.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class SageScreenHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const SageScreenHeader(
      {super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: InkResponse(
            onTap: () => Navigator.maybePop(context),
            radius: kSageMinTapTarget / 2,
            child: SizedBox(
              width: kSageMinTapTarget,
              height: kSageMinTapTarget,
              child: Icon(Icons.arrow_back, color: SageColors.ink),
            ),
          ),
        ),
        const SizedBox(width: SageSpace.xs),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: SageText.headline(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ...actions,
      ],
    );
  }
}
