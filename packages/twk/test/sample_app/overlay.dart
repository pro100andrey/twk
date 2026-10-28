part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _overlay() => const [
    SizedBox(
      height: 3,
      child: Row(
        children: [
          Panel(child: Text('panel')),
          OptionList(
            options: [
              Option('one', marks: [0]),
              Option('two', detail: '2'),
            ],
            highlighted: 0,
            rows: 2,
          ),
          Expanded(
            child: Overlay(
              child: CommandPalette(
                commands: [Command('Bump', intent: _Bump())],
                child: MenuBar(
                  menus: [
                    Menu(
                      '&File',
                      items: [
                        MenuItem('&Bump', intent: _Bump()),
                        MenuDivider(),
                        Menu(
                          '&More',
                          items: [MenuItem('&Wrap', checked: true)],
                        ),
                      ],
                    ),
                  ],
                  child: ContextMenu(
                    items: [MenuItem('&Bump', intent: _Bump())],
                    child: Center(
                      child: Popover(
                        open: false,
                        popover: Text('a popover'),
                        child: Tooltip(
                          message: 'a tooltip',
                          child: Text('centred'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: WindowLayer(
              windows: [Window(title: 'window', child: Text('in a window'))],
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ModalBarrier(alpha: 0x20),
                  Positioned(
                    right: 0,
                    top: 0,
                    // The bordered look: the raised one is a row taller
                    // than the room left here.
                    child: Dialog(
                      look: PanelLook.bordered,
                      title: 'dialog',
                      child: Text('modal'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ];
}
