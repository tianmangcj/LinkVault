import 'package:flutter/widgets.dart';

import '../../core/config/api_config.dart';
import '../../core/network/linkvault_api_client.dart';
import '../../core/network/token_storage.dart';
import '../../core/transfers/transfer_resume_service.dart';
import '../../core/transfers/transfer_resume_store.dart';

class AppDependencies {
  factory AppDependencies({
    required Uri apiBaseUrl,
    TokenStorage? tokenStorage,
    LinkVaultApi? apiClient,
    TransferTaskEvents? transferTaskEvents,
    TransferResumeStore? transferResumeStore,
  }) {
    final resolvedStorage = tokenStorage ?? const SecureTokenStorage();
    final resolvedTransferTaskEvents =
        transferTaskEvents ?? TransferTaskEvents();
    final resolvedApiClient =
        apiClient ??
        LinkVaultApiClient(
          baseUrl: apiBaseUrl,
          tokenStorage: resolvedStorage,
        );
    final resolvedTransferResumeStore =
        transferResumeStore ?? const SecureTransferResumeStore();
    return AppDependencies._(
      apiBaseUrl: apiBaseUrl,
      tokenStorage: resolvedStorage,
      transferTaskEvents: resolvedTransferTaskEvents,
      transferResumeStore: resolvedTransferResumeStore,
      transferResumeService: TransferResumeService(
        apiClient: resolvedApiClient,
        store: resolvedTransferResumeStore,
        onChanged: resolvedTransferTaskEvents.markChanged,
      ),
      apiClient: resolvedApiClient,
    );
  }

  const AppDependencies._({
    required this.apiBaseUrl,
    required this.tokenStorage,
    required this.transferTaskEvents,
    required this.transferResumeStore,
    required this.transferResumeService,
    required this.apiClient,
  });

  final Uri apiBaseUrl;
  final TokenStorage tokenStorage;
  final TransferTaskEvents transferTaskEvents;
  final TransferResumeStore transferResumeStore;
  final TransferResumeService transferResumeService;
  final LinkVaultApi apiClient;

  static AppDependencies bootstrap({Uri? apiBaseUrl}) {
    return AppDependencies(
      apiBaseUrl: apiBaseUrl ?? Uri.parse(ApiConfig.defaultBaseUrl),
    );
  }

  static Future<AppDependencies> bootstrapFromConfig() async {
    final apiBaseUrl = await ApiConfig.loadBaseUri();
    return AppDependencies(apiBaseUrl: apiBaseUrl);
  }
}

class TransferTaskEvents extends ChangeNotifier {
  int _version = 0;

  int get version => _version;

  void markChanged() {
    _version++;
    notifyListeners();
  }
}

class DependenciesScope extends InheritedWidget {
  const DependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DependenciesScope>();
    assert(scope != null, 'DependenciesScope is missing from the widget tree.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(DependenciesScope oldWidget) {
    return oldWidget.dependencies != dependencies;
  }
}
