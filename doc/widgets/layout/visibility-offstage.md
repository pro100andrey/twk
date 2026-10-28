---
title: "Visibility, Offstage"
group: "Layout"
package: "twk"
about: "A child hidden: Offstage keeps it laid out and running without painting it; Visibility takes its room away too, or keeps it."
image: "packages/gallery/doc/shots/layout/visibility-offstage.dark.svg"
image_light: "packages/gallery/doc/shots/layout/visibility-offstage.light.svg"
route: "#/layout/visibility-offstage"
---
# Visibility, Offstage

A child hidden: Offstage keeps it laid out and running without painting it; Visibility takes its room away too, or keeps it.

| Dark | Light |
| --- | --- |
| ![Visibility, Offstage, dark](../../../packages/gallery/doc/shots/layout/visibility-offstage.dark.svg) | ![Visibility, Offstage, light](../../../packages/gallery/doc/shots/layout/visibility-offstage.light.svg) |

## Code

The Dart that builds it, as the gallery's Code tab shows it with the
options as they start:

```dart
final theme = Theme.of(context);
return Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  children: [
    const Text('above the child'),
    Visibility(
      visible: false,
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        padding: const .x(1),
        child: const Text('the child'),
      ),
    ),
    const Text('below the child'),
  ],
);
```

## Options

What the gallery lets you change, and what each starts at:

| option | values | starts at |
| --- | --- | --- |
| widget | Visibility, Offstage | Visibility |
| hidden | on, off | true |
| keeps | nothing, state, size | nothing |
| replacement | on, off | false |

## More

- API: [`Visibility`](https://pub.dev/documentation/twk/latest/twk/Visibility-class.html), [`Offstage`](https://pub.dev/documentation/twk/latest/twk/Offstage-class.html).
- Also in Layout: [Box](box.md), [ColoredBox, DecoratedBox](coloredbox-decoratedbox.md), [Container](container.md), [Divider](divider.md), [Shadow](shadow.md), [Padding](padding.md), [Align, Center](align-center.md), [SizedBox](sizedbox.md), [ConstrainedBox](constrainedbox.md), [LimitedBox, OverflowBox](limitedbox-overflowbox.md), [FractionallySizedBox](fractionallysizedbox.md), [IntrinsicWidth/Height](intrinsicwidth-height.md), [Row, Column, Flex](row-column-flex.md), [Expanded, Spacer](expanded-spacer.md), [Stack, Positioned](stack-positioned.md), [Transform](transform.md), [ExpansionTile, Accordion](expansiontile-accordion.md), [Grid, GridPlacement](grid-gridplacement.md), [Wrap](wrap.md), [CustomPaint](custompaint.md), [SplitView](splitview.md), [DockArea](dockarea.md), [Scaffold](scaffold.md).
- Live in the gallery:
  `dart run packages/gallery/bin/gallery.dart --route='#/layout/visibility-offstage'`.
- [Layout](../layout.md) · [All groups](../README.md)
