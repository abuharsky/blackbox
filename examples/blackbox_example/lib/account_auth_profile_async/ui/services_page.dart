import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

import '../boxes/auth_box.dart';
import '../boxes/models.dart';
import '../boxes/profile_box.dart';
import '../boxes/selected_service_box.dart';
import '../boxes/services_loader_box.dart';
import 'box_card.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({
    super.key,
  });

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  Service? _service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blackbox Example')),
      body: BoxObserver(
        builder: (context) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Global(onSelected: (service) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _service = service;
                });
              });
            }),
            if (_service != null)
              const SizedBox(
                height: 12,
                child: Icon(Icons.arrow_downward_outlined),
              ),
            if (_service != null) _Service(service: _service!),
            const SizedBox(height: 24),
            Text(
              'Behavior to check:\n'
              '- Tap reload: ServicesLoader goes loading, selection becomes null, auth/profile reset.\n'
              '- Select a service: auth becomes available (session stays null until login).\n'
              '- Login: auth becomes loading, then data(session) or error.\n'
              '- When session appears: profile auto-loads.\n'
              '- Change service: auth/profile reset automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 12),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _Global extends StatefulWidget {
  final ValueChanged onSelected;

  const _Global({required this.onSelected});

  @override
  State<StatefulWidget> createState() => _GlobalState();
}

class _GlobalState extends State<_Global> {
  late final ServicesLoaderBox _servicesLoader;
  late final SelectedServiceBox _selectedService;

  late final VoidCallback _dispose;

  late final Connector _connector;

  @override
  void initState() {
    super.initState();

    _servicesLoader = ServicesLoaderBox();
    _selectedService = SelectedServiceBox(input: []);

    _dispose = _selectedService.listen((output) {
      widget.onSelected(output.value);
    });

    _connector = Connector.builder()
        .connect(_servicesLoader)
        .connectWith(
          _selectedService,
          dependencies: (d) => d.require(_servicesLoader),
        )
        .build(start: true);
  }

  @override
  void dispose() {
    super.dispose();
    _dispose();
    _connector.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) => Column(
        children: [
          _SectionHeader(title: 'Global layer'),
          BoxCard<List<Service>?>(
            title: 'ServicesLoaderBox',
            subtitle: const Text('output: List<Service>'),
            output: _servicesLoader.output,
            actions: [
              FilledButton.icon(
                onPressed: () => _servicesLoader.reload(),
                icon: const Icon(Icons.refresh),
                label: const Text('reload'),
              ),
            ],
            outputRenderer: (context, services) {
              if (services == null || services.isEmpty) {
                return const Text('— null');
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in services)
                    Chip(
                      label: Text(s.name),
                      avatar: const Icon(Icons.cloud, size: 16),
                    ),
                ],
              );
            },
          ),
          const SizedBox(
            height: 12,
            child: Icon(Icons.arrow_downward_outlined),
          ),
          BoxCard<Service?>(
            title: 'SelectedServiceBox',
            subtitle: const Text('output: Service?'),
            actions: const [],
            output: _selectedService.output,
            outputRenderer: (context, value) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _servicesLoader.output.when(
                    data: (services) {
                      return DropdownButton(
                        isExpanded: true,
                        value: value?.id,
                        hint: const Text('Select a service…'),
                        items: [
                          for (final s in services!)
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (s) => _selectedService
                            .select(services.where((e) => e.id == s).first),
                      );
                    },
                    loading: () => Text('loading'),
                    error: (e, _) => Text('err'),
                  ),
                  const SizedBox(height: 8),
                  Text('current: ${value?.name ?? 'null'}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Service extends StatefulWidget {
  final Service service;

  const _Service({required this.service});
  @override
  State<StatefulWidget> createState() => _ServiceState();
}

class _ServiceState extends State<_Service> {
  AuthBox? _auth;
  ProfileBox? _profile;

  Connector? _connector;

  Service? _service;

  void _initForService(Service service) {
    if (_service == service) return;

    _service = service;
    _auth = AuthBox(input: _service!);
    _profile = ProfileBox(input: AsyncData(null));

    _connector?.dispose();
    _connector = Connector.builder(context: widget.service)
        .connectWith(
          _auth!,
          dependencies: (d) => d.context,
        )
        .connectWith(
          _profile!,
          dependencies: (d) => d.output(_auth!),
        )
        .build(start: true);
  }

  @override
  void initState() {
    super.initState();
    _initForService(widget.service);
  }

  @override
  void didUpdateWidget(covariant _Service oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initForService(widget.service);
  }

  @override
  void dispose() {
    super.dispose();
    _connector?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) => Column(children: [
        _SectionHeader(title: 'Service layer'),
        BoxCard<Session?>(
          title: 'LazyAuthBox',
          subtitle: const Text('actions: login/logout | output: Session?'),
          output: _auth!.output,
          actions: [
            FilledButton(
              onPressed: () => _auth!.login(),
              child: const Text('login'),
            ),
            OutlinedButton(
              onPressed: () => _auth!.logout(),
              child: const Text('logout'),
            ),
          ],
          outputRenderer: (context, session) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('service: ${widget.service.name ?? 'null'}'),
                const SizedBox(height: 6),
                Text('session: ${session?.token ?? 'null'}'),
              ],
            );
          },
        ),
        const SizedBox(
          height: 12,
          child: Icon(Icons.arrow_downward_outlined),
        ),
        BoxCard<Profile?>(
          title: 'ProfileBox',
          subtitle: const Text('output: Profile?'),
          output: _profile!.output,
          outputRenderer: (context, profile) {
            if (profile == null) {
              return const Text('— null');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('service: ${profile.service.name}'),
                const SizedBox(height: 6),
                Text('name: ${profile.displayName}'),
                Text('userId: ${profile.userId}'),
              ],
            );
          },
        ),
      ]),
    );
  }
}
