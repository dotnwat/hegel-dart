/// A card that fits on the screen it was designed on.
///
/// The name and the role sit in a column with nothing telling it how wide it
/// may be, next to an avatar and a button that both insist on their own size.
/// On a wide screen with a short name it looks fine, which is the only
/// configuration it was ever looked at in.
library;

import 'package:flutter/material.dart';

/// A profile card, optionally laid out so that it survives.
class ProfileCard extends StatelessWidget {
  /// A card for [name] and [role]. [robust] repairs the layout.
  const ProfileCard({
    super.key,
    required this.name,
    required this.role,
    this.robust = false,
  });

  /// The name shown on the card.
  final String name;

  /// The role shown under it.
  final String role;

  /// Whether the text is given a width to live within.
  final bool robust;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: robust ? 1 : null,
          overflow: robust ? TextOverflow.ellipsis : null,
        ),
        Text(
          role,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: robust ? 1 : null,
          overflow: robust ? TextOverflow.ellipsis : null,
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const CircleAvatar(radius: 24, child: Text('A')),
            const SizedBox(width: 12),
            // The fix is one word. Without it the column takes whatever width
            // its text wants and the row overflows by the difference.
            if (robust) Expanded(child: text) else text,
            const SizedBox(width: 12),
            // The button has to be able to give way too. A column that can
            // shrink next to a button that cannot is a row that still
            // overflows, just later and on a narrower phone.
            if (robust)
              Flexible(
                child: FilledButton(
                  onPressed: () {},
                  child: const Text(
                    'Follow',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            else
              FilledButton(onPressed: () {}, child: const Text('Follow')),
          ],
        ),
      ),
    );
  }
}

/// [card] on a screen, ready to pump.
Widget profileScreen(Widget card) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: Padding(padding: const EdgeInsets.all(16), child: card),
  ),
);
