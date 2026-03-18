import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

import '../boxes/api.dart';
import '../boxes/auth_box.dart';
import '../boxes/models.dart';
import '../boxes/profile_box.dart';
import '../boxes/selected_service_box.dart';
import '../boxes/services_loader_box.dart';
import 'box_card.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _api = Api();
  Service? _service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blackbox Example')),
      body: BoxObserver(
        builder: (context) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Global(
              api: _api,
              onSelected: (service) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() => _service = service);
                });
              },
            ),
            if (_service != null) ...[
              const SizedBox(
                height: 12,
                child: Icon(Icons.arrow_downward_outlined),
              ),
              _Service(api: _api, service: _service!),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global layer: services loader → selected service
// ---------------------------------------------------------------------------

class _Global extends StatefulWidget {
  final Api api;
  final ValueChanged<Service?> onSelected;

  const _Global({required this.api, required this.onSelected});

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

    _servicesLoader = ServicesLoaderBox(widget.api);
    _selectedService = SelectedServiceBox(input: const []);

    _cancelSelected = _selectedService.listenSync((output) {
      widget.onSelected(output.value);
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
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) => Column(
        children: [
          _SectionHeader(title: 'Global layer'),
          BoxCard<List<Service>>(
            title: 'ServicesLoaderBox',
            subtitle: const Text('async | output: List<Service>'),
            output: _servicesLoader.output,
            actions: [
              FilledButton.icon(
                onPressed: _servicesLoader.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('refresh'),
              ),
            ],
            outputRenderer: (context, services) {
              if (services.isEmpty) return const Text('empty');
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
            subtitle: const Text('sync | persistent | output: Service?'),
            actions: const [],
            output: _selectedService.output,
            outputRenderer: (context, value) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _servicesLoader.output.when(
                    data: (services) {
                      return DropdownButton<String>(
                        isExpanded: true,
                        value: value?.id,
                        hint: const Text('Select a service…'),
                        items: [
                          for (final s in services)
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (id) => _selectedService.select(
                          services.firstWhere((s) => s.id == id),
                        ),
                      );
                    },
                    loading: () => const Text('loading…'),
                    error: (e, _) => Text('error: $e'),
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

// ---------------------------------------------------------------------------
// Service layer: auth → profile (created per selected service)
// ---------------------------------------------------------------------------

class _Service extends StatefulWidget {
  final Api api;
  final Service service;

  const _Service({required this.api, required this.service});

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

    _auth = AuthBox(widget.api, input: service);
    _profile = ProfileBox(widget.api, input: null);

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
    _initForService(widget.service);
  }

  @override
  void didUpdateWidget(covariant _Service oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initForService(widget.service);
  }

  @override
  void dispose() {
    _graph?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BoxObserver(
      builder: (_) => Column(children: [
        _SectionHeader(title: 'Service layer (${widget.service.name})'),
        BoxCard<Session?>(
          title: 'AuthBox',
          subtitle: const Text('async | persistent | output: Session?'),
          output: _auth!.output,
          actions: [
            FilledButton(
              onPressed: _auth!.login,
              child: const Text('login'),
            ),
            OutlinedButton(
              onPressed: _auth!.logout,
              child: const Text('logout'),
            ),
          ],
          outputRenderer: (context, session) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('service: ${widget.service.name}'),
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
          subtitle: const Text('async | output: Profile?'),
          output: _profile!.output,
          outputRenderer: (context, profile) {
            if (profile == null) return const Text('null');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

// ---------------------------------------------------------------------------

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
