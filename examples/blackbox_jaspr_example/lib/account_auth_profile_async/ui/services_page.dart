import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../boxes/api.dart';
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
  final _api = Api();
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
            'Services loader → selected service (persistent) → auth (persistent) → profile. '
            'Select a service, login, then switch service to see cascading reset.',
          ),
        ],
        styles: const Styles(raw: {
          'margin': '0 0 1rem',
          'line-height': '1.7',
          'color': '#334155',
        }),
      ),
      _Global(api: _api, onSelected: _setSelectedService),
      if (_service != null)
        div([
          const _SectionArrow(),
          _Service(api: _api, service: _service!),
        ]),
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
  const _Global({required this.api, required this.onSelected});

  final Api api;
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

    _servicesLoader = ServicesLoaderBox(component.api);
    _selectedService = SelectedServiceBox(input: const <Service>[]);
    _cancelSelected = _selectedService.listenSync((output) {
      component.onSelected(output.value);
    });

    _graph = Graph.builder()
        .add(_servicesLoader)
        .add(
          _selectedService,
          input: (d) => d.whenReady(_servicesLoader),
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
        BoxCard<List<Service>>(
          title: 'ServicesLoaderBox',
          subtitle: _subtitle('Fetches available services from API.'),
          output: _servicesLoader.output,
          actions: [
            _ActionButton(
              label: 'refresh',
              onClick: _servicesLoader.refresh,
            ),
          ],
          outputRenderer: (_, services) {
            if (services.isEmpty) {
              return p([Component.text('services: none')],
                  styles: _plainTextStyles);
            }
            return ul(
              [
                for (final service in services)
                  li([Component.text(service.name)],
                      styles: const Styles(
                          raw: {'margin-bottom': '0.2rem'})),
              ],
              styles: const Styles(
                  raw: {'margin': '0', 'padding-left': '1.2rem'}),
            );
          },
        ),
        const _SectionArrow(),
        BoxCard<Service?>(
          title: 'SelectedServiceBox',
          subtitle:
              _subtitle('Persists the last chosen service in localStorage.'),
          output: _selectedService.output,
          outputRenderer: (_, selectedValue) {
            final servicePicker = switch (_servicesLoader.output) {
              AsyncData<List<Service>>(:final value)
                  when value.isNotEmpty =>
                div(
                  [
                    for (final service in value)
                      _ActionButton(
                        label: service.name,
                        active: service.id == selectedValue?.id,
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
                  [Component.text('Waiting for services to load…')],
                  styles: const Styles(
                      raw: {'margin': '0 0 0.9rem', 'color': '#64748b'}),
                ),
            };

            return div([
              servicePicker,
              p(
                [Component.text(
                    'current: ${selectedValue?.name ?? 'null'}')],
                styles: _plainTextStyles,
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _Service extends StatefulComponent {
  const _Service({required this.api, required this.service});

  final Api api;
  final Service service;

  @override
  State<_Service> createState() => _ServiceState();
}

class _ServiceState extends State<_Service> {
  AuthBox? _auth;
  ProfileBox? _profile;
  Graph? _graph;
  Service? _currentService;

  void _initForService(Service service) {
    if (_currentService == service) return;
    _currentService = service;

    _graph?.dispose();

    _auth = AuthBox(component.api, input: service);
    _profile = ProfileBox(component.api, input: null);

    _graph = Graph.builder()
        .add(_auth!)
        .add(
          _profile!,
          input: (d) => d.whenReady(_auth!),
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
          title: 'AuthBox',
          subtitle: _subtitle('Login/logout with per-service persistence.'),
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
          title: 'ProfileBox',
          subtitle:
              _subtitle('Fetches profile when session is available.'),
          output: _profile!.output,
          outputRenderer: (_, profile) {
            if (profile == null) {
              return p([Component.text('profile: null')],
                  styles: _plainTextStyles);
            }
            return div([
              p([Component.text('name: ${profile.displayName}')],
                  styles: _plainTextStyles),
              p([Component.text('userId: ${profile.userId}')],
                  styles: _plainTextStyles),
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
    styles: const Styles(raw: {
      'margin': '0.45rem 0 0',
      'font-size': '0.94rem',
      'line-height': '1.65',
      'color': '#475569',
    }),
  );
}

const Styles _plainTextStyles = Styles(raw: {
  'margin': '0 0 0.35rem',
  'line-height': '1.6',
});
