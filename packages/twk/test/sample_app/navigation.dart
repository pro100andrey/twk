part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _navigation() => [
    SizedBox(
      height: 1,
      child: Row(
        children: [
          Expanded(
            child: Navigator(
              home: const PopScope<Object?>(canPop: false, child: Text('home')),
              routes: {'/next': (_) => const Text('next')},
            ),
          ),
          const Expanded(
            child: Scaffold(
              sidebar: Text('sidebar'),
              body: Text('body'),
              keyHints: false,
              sidebarWidth: 8,
              sidebarSide: SidebarSide.right,
              resizableSidebar: true,
              collapsedBelow: 20,
            ),
          ),
        ],
      ),
    ),
    SizedBox(
      height: 1,
      child: Row(
        gap: 1,
        children: [
          Expanded(
            child: Overlay(
              child: Breadcrumbs(
                items: const ['Root', 'lib', 'src'],
                onSelected: (_) {},
              ),
            ),
          ),
          Expanded(
            child: Pagination(
              page: 0,
              pageCount: 5,
              itemCount: 50,
              pageSize: 10,
              onChanged: (_) {},
            ),
          ),
        ],
      ),
    ),
    SizedBox(
      height: 3,
      child: Stepper(
        steps: [
          Step(
            title: 'Info',
            subtitle: 'the name',
            content: const Text('name'),
            validate: () => null,
          ),
          const Step(
            title: 'Skipped',
            content: Text('skipped'),
            state: StepState.disabled,
          ),
          const Step(title: 'Done', content: Text('done')),
        ],
        linear: false,
        onFinished: () {},
        onStepChanged: (_) {},
      ),
    ),
  ];
}
