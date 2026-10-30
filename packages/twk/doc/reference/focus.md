# twk reference: `focus`

[The reference](README.md) · `lib/src/focus/`, `test/focus/`

The focus tree.

## `Focus`

`Focus(focusNode:, autofocus:, onKeyEvent:, canRequestFocus:,
skipTraversal:, descendantsAreFocusable:, debugLabel:, child:)` puts a
`FocusNode`, its own or the one given (whose settings it sets where they are
not null), in the tree under the node of the nearest `Focus` or `FocusScope`
above it, and `FocusScope(node:, …)` a `FocusScopeNode`; a `GlobalKey` that
moves the widget moves the node with its focus, and another `focusNode`
takes the place of the one before, with the focus.

## `Focus.of`

`Focus.of(context)` (`maybeOf`, with or without a dependency) finds the
nearest node and rebuilds the context when its `hasFocus` or
`hasPrimaryFocus` changes;

## `FocusScope.of`

`FocusScope.of` its scope. A `FocusNode`, a `ChangeNotifier` whose listeners
are told at the start of the next build when its focus changed, takes the
primary focus with `requestFocus` and gives it up with `unfocus`, to the
nearest scope above it; it cannot take it while `canRequestFocus` is false
or a node above it keeps it from the nodes below (`descendantsAreFocusable`
false, as a `TabView` does for the tabs it hides), and set so while it has
it (a button disabled, a window minimised), it passes it on at the next
flush to the node of its scope that Tab stops at right after its place, else
the one right before it, else the scope, so that a keyboard user keeps the
place (Flutter gives it to the node the scope focused last). Tab and
Shift+Tab (`nextFocus`, `previousFocus`) move the focus through the nodes of
the nearest scope that can take it and do not `skipTraversal`, in the order
of the tree (depth first, the children of a widget in order), the first
after the last; a scope inside is one stop, which Tab does not leave and
which, entered, focuses the node it focused last (`focusedChild`) or its
first. The first node of a scope mounted with `autofocus` while the scope
has no focused node gets the focus, shown in the frame that mounts it; when
the focused node leaves the tree, the focus passes on the same way in the
frame that removes it, to the node that took its place or the next after
where it was; when its scope left with it, or it was a scope itself (a
dialog closed), the scope above gives it to the node it focused last.

## `FocusBuilder`

`FocusBuilder(builder: (context, hasFocus, child) => …, child:)` builds
again as the focus enters or leaves its subtree, the `child` handed to it
not, and takes no focus itself, no stop of Tab: a box whose border is lit
while the focus is in it, in one widget.

## `ExcludeFocus`

`ExcludeFocus(excluding: true, child:)` keeps the focus out of a subtree:
Tab, autofocus and `requestFocus` pass its nodes by, and turned on while a
node in it has the focus, the focus leaves it at the next flush as it leaves
a node that can no longer take it, the nodes taking it again once it is
turned off (an autofocus asked for meanwhile does not come back). The app's
`FocusManager` (`AppBinding.focusManager`: `rootScope`, `primaryFocus`)
gives a key to the nodes of its `keyPath` in turn until an `onKeyEvent`
returns `KeyEventResult.handled`: the deepest node a walk down from the
primary focus reaches, going on as long as a node has a single node below it
that cannot take the focus, is not a scope and lets the nodes below it take
it (`descendantsAreFocusable`), then the nodes above that one, the primary
focus among them, a call for each, the widget tree not walked. So the layers
right below a node (`KeyBindings`, `Shortcuts`) get its keys from the moment
it has the focus, a key typed right after Tab in the same read too, as do
those below a scope that has the focus itself (after `unfocus`, or once the
focused node left the tree); while no node has the focus the root scope
stands for it, so a layer around the whole app gets a key and one around a
part of it does not. A node that can take the focus gets no key it was not
given. While a node holds the keys (`FocusNode.holdKeys`, `holdsKeys`),
until it calls `releaseKeys`, another node holds them, the primary focus
moves or it leaves the tree, the key path starts at it, past the primary
focus and the nodes between. A key binding names keys as `KeyCombo.parse`
reads them: the modifiers `ctrl`, `alt`, `shift` and `super`, in any order,
each once, then the key, joined by `+` (`ctrl+s`, `shift+tab`); the key is
one character, which stands for itself (`+` comes last: `ctrl++`), `space`,
or a `KeyCode`'s name in lower case (`enter`, `pageup`, `f1`); only a
character has a case (`A` is `shift+a`, `ctrl+A` is `ctrl+shift+a`), and
Shift alone with a character that has no case names no key; keys pressed one
after another are one space apart (`parseSequence`: `ctrl+x ctrl+s`; with
`leader:`, `leader` stands for that key). A string that is not one is a
`FormatException` naming the part that is wrong, and the name meant where
that is plain (`Enter`, `esc`, `cmd`); `toString` writes a combo as it is
parsed (`KeyCombo(code)`, `KeyCombo.char`, `KeyCombo.fromEvent`, and
`accepts` for a press or a repeat of the key). Without the kitty keyboard
protocol a terminal sends some combos as others: `ctrl+i` as `tab`, `ctrl+m`
and `ctrl+j` as `enter`, `ctrl+[` as `escape`, `ctrl+h` as `backspace`,
`ctrl+2` as `ctrl+space`, Ctrl, Shift and a letter as Ctrl and the letter,
Ctrl or Shift with `enter` or `escape` as the key alone, and Super not at
all.

## `KeyBindings`

`KeyBindings({'up': () => setState(() => _n++), 'q': () =>
AppBinding.of(context).quit()}, child: …)` (the counter of
`test/focus/shortcuts_test.dart`) binds keys to callbacks, and
`Shortcuts({'ctrl+s': SaveIntent()}, child: …)` to `Intent`s, which the
nearest enabled `Action` for the intent's type in the `Actions` above the
node the key started at does (`CallbackAction`; `Actions.maybeFind`,
`Actions.maybeInvoke`); `.combos` take `KeyCombo`s, each bound alone, and
`hints` say what the keys do (`{'ctrl+s': 'save'}`). Each is a layer of the
focus tree, a node that cannot take the focus and that Tab passes by: the
layer nearest the focus goes first, and one around the whole app gets every
key the others leave. A key bound to null, or to an intent no enabled action
does, passes on, as does a release; a name that is not a key, two names of
one key, or a hint for a key the layer does not bind fails the layer's
build. A name of keys pressed one after another binds a sequence: `'g g'`,
`'ctrl+x ctrl+s'`, `'leader f'`, `leader` the key the nearest `LeaderKey`
above names (`LeaderKey(',', child: …)`; `space` without one; another leader
rebuilds the layers, and a name that is not one key fails their build). The
layer holds the first keys of a sequence it binds (`holdKeys`), so the next
keys come to it before the focused node (a text field does not take the `s`
of `ctrl+x s`), and the key that ends the sequence does it. Within a layer,
a key bound alone that also starts a sequence (`g` and `g g`) waits for the
next: a key that does not go on with the sequence, or `sequenceTimeout` (1
s; null waits for ever) passing, does the longest of the keys held that is
bound and taken, and the keys after it are pressed anew. Keys held that no
binding takes, a sequence bound to null or to an intent no enabled action
does among them, are dropped with the key that broke them
(`UnmatchedKeys.drop`, the default, so Escape lets a sequence go, as in
Emacs), or with `UnmatchedKeys.replay`, as in Vim, go on in turn: the first
to the nodes above the layer, where a sequence may take it too, the others
pressed anew, none of them reaching the `InputListener`s, then the key that
broke them from the focused node up. The focus moving drops them. Across
layers the nearest goes first: a key a nearer layer binds alone is done at
once and hides the sequences above that start with it, and a nearer sequence
holds its first key from the bindings above, which only a replay reaches.

## `FocusManager.activeKeys`

`FocusManager.activeKeys` lists the keys the layers on the key path take now
(`ActiveKey`: its `combo`, its `hint` and its `binding`, the callback or the
intent its layer binds it to): the nearest layer's first, each layer's in
the order of its map, a key once, by the rule a key pressed follows, a
sequence by its first key with the keys after it in `then`; while a layer
holds the first keys of a sequence, only the keys that can follow them
(`combo` the next, `then` the rest); those a node takes in its own
`onKeyEvent` are not listed.

## `ActiveKey.label`

`ActiveKey.label(keyLabel)` names its keys, each by `keyLabel`
(`KeyCombo.toString` by default), a space apart as `parseSequence` reads
them (`ctrl+x ctrl+s`), and `toString` adds its hint (`g g top`).

## `FocusManager.keysChanged`

`FocusManager.keysChanged` tells when they may have changed: other nodes on
the key path, or a node on it that marked its keys changed
(`FocusNode.markKeysChanged`), as a layer built with other keys or hints, or
below `Actions` built with other actions, does, and a layer as it starts
holding keys, holds one more and lets them go; a layer built with a key
bound to another callback alone, as a closure made in each build is, does
not tell it, and one bound to another intent does;

## `ActiveItem`

`ActiveItem(active:, column: 0, child:)` marks the item a widget focused as
a whole acts on, as the web's `aria-activedescendant` (a list's cursor row,
every item wrapped, `active` on one): the hidden cursor rests on its
`column` of its first row while it is in the focused widget (`restCursor`),
one active in another, as a table's cursor cell in its selected row, winning
