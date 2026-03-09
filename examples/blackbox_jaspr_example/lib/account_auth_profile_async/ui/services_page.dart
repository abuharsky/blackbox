import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../boxes/auth_box.dart';
import '../boxes/models.dart';
import '../boxes/profile_box.dart';
import '../boxes/selected_service_box.dart';
import '../boxes/services_loader_box.dart';
import 'box_card.dart';

class ServicesPage extends StatefulComponent {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  Service? _service;

  void _setSelectedService(Service? service) {
    if (_service == service) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() => _service = service);
    });
  }

  @override
  Component build(BuildContext context) {
    return section([
      h2(
        [Component.text('Account + auth + profile flow')],
        styles: const Styles(raw: {
          'margin': '0 0 0.5rem',
          'font-size': '1.4rem',
        }),
      ),
      p(
        [
          Component.text(
            'This demo chains a services loader, a persistent selected service, a lazy auth box and an async profile box.',
          ),
        ],
        styles: const Styles(raw: {
          'margin': '0 0 1rem',
          'line-height': '1.7',
          'color': '#334155',
        }),
      ),
      _Global(onSelected: _setSelectedService),
      if (_service != null)
        div([
          const _SectionArrow(),
          _Service(service: _service!),
        ]),
      article([
        p(
          [
            Component.text(
              'Behavior to check: reload services, select a service, login, observe auth/profile recomputation, then switch the service and watch dependent boxes reset.',
            ),
          ],
          styles: const Styles(raw: {
            'margin': '0',
            'line-height': '1.7',
            'color': '#475569',
          }),
        ),
      ], styles: const Styles(raw: {
        'margin-top': '1rem',
        'padding': '1rem 1.2rem',
        'border-radius': '1rem',
        'background': 'rgba(15,23,42,0.04)',
      })),
    ]);
  }
}

class _SectionArrow extends StatelessComponent {
  const _SectionArrow();

  @override
  Component build(BuildContext context) {
    return div(
      [Component.text('↓')],
      styles: const Styles(raw: {
        'text-align': 'center',
        'font-size': '1.35rem',
        'color': '#f97316',
        'padding': '0.25rem 0',
      }),
    );
  }
}

typedef _ServiceSelected = void Function(Service? service);

class _Global extends StatefulComponent {
  const _Global({
    required this.onSelected,
  });

  final _ServiceSelected onSelected;

  @override
  State<_Global> createState() => _GlobalState();
}

class _GlobalState extends State<_Global> {
  late final ServicesLoaderBox _servicesLoader;
  late final SelectedServiceBox _selectedService;
  late final Cancel _cancelSelected;
  late final Graph _graph;

  @override
  void initState() {
    super.initState();

    _servicesLoader = ServicesLoaderBox();
    _selectedService = SelectedServiceBox(input: const <Service>[]);
    _cancelSelected = _selectedService.listen((output) {
      component.onSelected(output.value);
    });

    _graph = Graph.builder()
        .add(_servicesLoader)
        .addWith(
          _selectedService,
          dependencies: (d) => d.require(_servicesLoader),
        )
        .build(start: true);
  }

  @override
  void dispose() {
    _cancelSelected();
    _graph.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return BoxObserver(
      builder: (_) => div([
        BoxCard<List<Service>?>(
          title: 'Services loader',
          subtitle: _subtitle('Simulates remote service discovery.'),
          output: _servicesLoader.output,
          actions: [
            _ActionButton(
              label: 'reload services',
              onClick: _servicesLoader.reload,
            ),
          ],
          outputRenderer: (_, services) {
            if (services == null || services.isEmpty) {
              return p([Component.text('services: none')], styles: _plainTextStyles);
            }

            return ul(
              [
                for (final service in services)
                  li([Component.text(service.name)], styles: const Styles(raw: {
                    'margin-bottom': '0.2rem',
                  })),
              ],
              styles: const Styles(raw: {
                'margin': '0',
                'padding-left': '1.2rem',
              }),
            );
          },
        ),
        const _SectionArrow(),
        BoxCard<Service?>(
          title: 'Selected service',
          subtitle: _subtitle('Persists the last chosen service in localStorage.'),
          output: _selectedService.output,
          outputRenderer: (_, selectedValue) {
            final servicePicker = switch (_servicesLoader.output) {
              AsyncData<List<Service>?>(:final value)
                  when value != null && value.isNotEmpty =>
                div(
                  [
                    for (final service in value)
                      _ActionButton(
                        label: service.name,
                        active: service.id ==
                            _selectedServiceId(
                              services: value,
                              current: selectedValue,
                            ),
                        onClick: () => _selectedService.select(service),
                      ),
                  ],
                  styles: const Styles(raw: {
                    'display': 'flex',
                    'flex-wrap': 'wrap',
                    'gap': '0.65rem',
                    'margin-bottom': '0.9rem',
                  }),
                ),
              _ => p(
                  [Component.text('Select a service when the loader returns data.')],
                  styles: const Styles(raw: {
                    'margin': '0 0 0.9rem',
                    'color': '#64748b',
                  }),
                ),
            };

            return div([
              servicePicker,
              p(
                [Component.text('current: ${selectedValue?.name ?? 'null'}')],
                styles: _plainTextStyles,
              ),
            ]);
          },
        ),
      ]),
    );
  }

  String? _selectedServiceId({
    required List<Service> services,
    required Service? current,
  }) {
    if (current == null) return null;
    return services.any((service) => service.id == current.id)
        ? current.id
        : null;
  }
}

class _Service extends StatefulComponent {
  const _Service({
    required this.service,
  });

  final Service service;

  @override
  State<_Service> createState() => _ServiceState();
}

class _ServiceState extends State<_Service> {
  AuthBox? _auth;
  ProfileBox? _profile;
  Graph? _graph;
  Service? _service;

  void _initForService(Service service) {
    if (_service == service) return;

    _service = service;
    _auth = AuthBox(input: service);
    _profile = ProfileBox(input: const AsyncData<Session?>(null));

    _graph?.dispose();
    _graph = Graph.builder(context: service)
        .addWith(
          _auth!,
          dependencies: (d) => d.context,
        )
        .addWith(
          _profile!,
          dependencies: (d) => d.output(_auth!),
        )
        .build(start: true);
  }

  @override
  void initState() {
    super.initState();
    _initForService(component.service);
  }

  @override
  void didUpdateComponent(covariant _Service oldComponent) {
    super.didUpdateComponent(oldComponent);
    _initForService(component.service);
  }

  @override
  void dispose() {
    _graph?.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return BoxObserver(
      builder: (_) => div([
        BoxCard<Session?>(
          title: 'Lazy auth box',
          subtitle: _subtitle('Handles login/logout and persists the last session per service.'),
          output: _auth!.output,
          actions: [
            _ActionButton(label: 'login', onClick: _auth!.login),
            _ActionButton(label: 'logout', onClick: _auth!.logout),
          ],
          outputRenderer: (_, session) {
            return div([
              p(
                [Component.text('service: ${component.service.name}')],
                styles: _plainTextStyles,
              ),
              p(
                [Component.text('session: ${session?.token ?? 'null'}')],
                styles: _plainTextStyles,
              ),
            ]);
          },
        ),
        const _SectionArrow(),
        BoxCard<Profile?>(
          title: 'Profile box',
          subtitle: _subtitle('Depends on the auth output and resolves profile data when a session exists.'),
          output: _profile!.output,
          outputRenderer: (_, profile) {
            if (profile == null) {
              return p([Component.text('profile: null')], styles: _plainTextStyles);
            }

            return div([
              p(
                [Component.text('service: ${profile.service.name}')],
                styles: _plainTextStyles,
              ),
              p(
                [Component.text('name: ${profile.displayName}')],
                styles: _plainTextStyles,
              ),
              p(
                [Component.text('userId: ${profile.userId}')],
                styles: _plainTextStyles,
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessComponent {
  const _ActionButton({
    required this.label,
    required this.onClick,
    this.active = false,
  });

  final String label;
  final VoidCallback onClick;
  final bool active;

  @override
  Component build(BuildContext context) {
    return button(
      [Component.text(label)],
      onClick: onClick,
      styles: Styles(
        raw: {
          'border': active ? '1px solid #0f172a' : '1px solid #fdba74',
          'background': active ? '#0f172a' : '#fff7ed',
          'color': active ? '#fff' : '#9a3412',
          'padding': '0.65rem 0.9rem',
          'border-radius': '0.8rem',
          'font-weight': '600',
          'cursor': 'pointer',
        },
      ),
    );
  }
}

Component _subtitle(String text) {
  return p(
    [Component.text(text)],
    styles: const Styles(
      raw: {
        'margin': '0.45rem 0 0',
        'font-size': '0.94rem',
        'line-height': '1.65',
        'color': '#475569',
      },
    ),
  );
}

const Styles _plainTextStyles = Styles(raw: {
  'margin': '0 0 0.35rem',
  'line-height': '1.6',
});
