---
title: "Padding"
group: "Layout"
package: "twk"
about: "Empty cells around a child."
image: "packages/gallery/doc/shots/layout/padding.dark.svg"
image_light: "packages/gallery/doc/shots/layout/padding.light.svg"
route: "#/layout/padding"
---
# Padding

Empty cells around a child.

| Dark | Light |
| --- | --- |
| ![Padding, dark](../../../packages/gallery/doc/shots/layout/padding.dark.svg) | ![Padding, light](../../../packages/gallery/doc/shots/layout/padding.light.svg) |

## Code

The Dart that builds it, as the gallery's Code tab shows it with the
options as they start:

```dart
final theme = Theme.of(context);
return Box(
  border: .all(type: .rounded, style: theme.border),
  child: Padding(
    padding: const .x(4),
    child: Box(
      style: theme.selection,
      child: const Text('the child,\npadded from the box'),
    ),
  ),
);
```

## Options

What the gallery lets you change, and what each starts at:

| option | values | starts at |
| --- | --- | --- |
| padding | all 1, x 4, y 2, left 8, left 3, top 1 | x 4 |

## More

- API: [`Padding`](https://pub.dev/documentation/twk/latest/twk/Padding-class.html).
- Also in Layout: [Box](box.md), [ColoredBox, DecoratedBox](coloredbox-decoratedbox.md), [Container](container.md), [Divider](divider.md), [Shadow](shadow.md), [Align, Center](align-center.md), [SizedBox](sizedbox.md), [ConstrainedBox](constrainedbox.md), [LimitedBox, OverflowBox](limitedbox-overflowbox.md), [FractionallySizedBox](fractionallysizedbox.md), [IntrinsicWidth/Height](intrinsicwidth-height.md), [Row, Column, Flex](row-column-flex.md), [Expanded, Spacer](expanded-spacer.md), [Stack, Positioned](stack-positioned.md), [Transform](transform.md), [Visibility, Offstage](visibility-offstage.md), [ExpansionTile, Accordion](expansiontile-accordion.md), [Grid, GridPlacement](grid-gridplacement.md), [Wrap](wrap.md), [CustomPaint](custompaint.md), [SplitView](splitview.md), [DockArea](dockarea.md), [Scaffold](scaffold.md).
- Live in the gallery:
  `dart run packages/gallery/bin/gallery.dart --route='#/layout/padding'`.
- [Layout](../layout.md) · [All groups](../README.md)
