// The differences the Code check expects: pages whose stage and Code
// cannot agree by their nature. One that differs is reported `expected`,
// the reason before its cause, its first differing cells still listed, so
// that a difference that grows is seen; one that matches is reported
// `matches`, and its entry can go. Keep the reason to what makes the
// difference unavoidable.

/// By the page's key (`group/page`), why its Code cannot draw what its
/// stage does.
const knownCode = {
  'style/gradientbackground':
      "the colours flow: the Code's AnimationController counts from its "
      "ticker's first tick, a frame (1/60 s) after the stage's clock, so the "
      'channels are a step off',
  'style/gradientforeground':
      "the colours flow: the Code's AnimationController counts from its "
      "ticker's first tick, a frame (1/60 s) after the stage's clock, so the "
      'channels are a step off',
  'controls/filepicker':
      "the Code's picker lists the directory it runs in "
      "(Directory.current), the stage the gallery's example tree",
  'controls/keyhintsbar':
      "no focus in the Code's run: with the focus outside the example the "
      "stage's bar shows the gallery's own keys, which the Code alone does "
      'not have',
  'animation/dissolve-fractionaltranslation':
      'Dissolve scatters its cells by their position on the screen: the '
      "Code runs at the screen's top left, not where the stage is",
  'focus-and-keys/keybindings-leaderkey':
      "no focus in the Code's run: the stage shows no hints with the focus "
      "outside the example, twk's KeyHintsBar the bindings above it",
  'focus-and-keys/shortcuts-actions':
      "no focus in the Code's run: the stage shows no hints with the focus "
      "outside the example, twk's KeyHintsBar the bindings above it",
  'layout/scaffold':
      "no focus in the Code's run: with nothing focused after its first "
      "frame twk's Scaffold focuses its body's first node (the New note "
      'button, its keys in the bar); the stage leaves the focus in the '
      "gallery's list, the bar showing the list's keys",
  'debugging/console':
      "the Code's records have the wall clock's time (DateTime.now()); the "
      "stage is the page at the route's time with the last records already "
      'there, the Code a program run from 0 whose timer has logged one each '
      '700 ms since',
  'debugging/frameoverlay':
      'the overlay shows what twk measured in this run (times in µs vary '
      'from run to run, the medians are of its frames); the stage shows '
      'typical numbers of runs in a pseudo-terminal',
};
