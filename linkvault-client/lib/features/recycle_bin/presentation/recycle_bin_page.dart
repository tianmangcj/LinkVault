import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/folder_picker_dialog.dart';
import '../../../shared/widgets/vault_widgets.dart';
import '../../files/presentation/file_list_page.dart';

const _recycleBinRetention = Duration(days: 10);

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  late Future<PageResult<FileNode>> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _load();
      _initialized = true;
    }
  }

  Future<PageResult<FileNode>> _load() {
    return DependenciesScope.of(context).apiClient.recycleBin();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _restore(FileNode node) async {
    try {
      await DependenciesScope.of(context).apiClient.restoreFile(node.id);
      if (mounted) {
        _reload();
      }
    } catch (error) {
      final apiError = normalizeApiError(error);
      if (apiError.code == 'restore_original_path_missing') {
        await _restoreToSelectedFolder(node);
        return;
      }
      _showError(error);
    }
  }

  Future<void> _restoreToSelectedFolder(FileNode node) async {
    if (!mounted) {
      return;
    }
    final targetId = await showFolderPickerDialog(
      context,
      title: '选择恢复位置',
      loadFolders: (parentId) => DependenciesScope.of(
        context,
      ).apiClient.files(type: FileNodeType.folder, parentId: parentId),
    );
    if (targetId == null || !mounted) {
      return;
    }
    try {
      await DependenciesScope.of(context).apiClient.restoreFile(
        node.id,
        useOriginalPath: false,
        parentId: folderPickerTargetToParentId(targetId),
      );
      if (mounted) {
        _reload();
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _purge(FileNode node) async {
    final confirmed = await showAppConfirmation(
      context,
      title: '彻底删除',
      message: '要彻底删除这条记录吗？删除后无法恢复。',
      confirmLabel: '彻底删除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await DependenciesScope.of(context).apiClient.purgeFile(node.id);
      if (mounted) {
        _reload();
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _empty() async {
    final confirmed = await showAppConfirmation(
      context,
      title: '清空回收站',
      message: '要清空回收站吗？其中所有记录都会被彻底删除，且无法恢复。',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await DependenciesScope.of(context).apiClient.emptyRecycleBin();
      if (mounted) {
        _reload();
      }
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    _showMessage(normalizeApiError(error).message);
  }

  void _showMessage(String message) {
    showAppNotice(context, message, type: AppNoticeType.error);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '回收站',
      currentRoute: AppRoute.recycleBin,
      body: FixedSimplePage(
        header: PageIntro(
          title: '回收站',
          leadingIcon: Icons.restore_from_trash_outlined,
          trailing: TextButton.icon(
            onPressed: _empty,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('清空'),
          ),
        ),
        expandedChild: FutureBuilder<PageResult<FileNode>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final connectionFailure =
                !loading &&
                snapshot.hasError &&
                isNetworkConnectionFailure(snapshot.error!);
            if (connectionFailure) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showNetworkConnectionFailureSnackBar(context);
              });
            }
            final items = loading || snapshot.hasError
                ? const <FileNode>[]
                : snapshot.data?.items ?? const <FileNode>[];
            return SimplePanel(
              title: '已删除文件',
              expandChild: true,
              child: items.isEmpty && !loading && !snapshot.hasError
                  ? const _EmptyState()
                  : ListView.separated(
                      primary: false,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SectionDivider(),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return SimpleListRow(
                          icon: item.type == FileNodeType.folder
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                          title: item.name,
                          subtitle:
                              '${formatBytes(item.sizeBytes)} · ${_recycledAtLabel(item)} · ${_autoDeleteLabel(item)}',
                          trailing: _RecycleActions(
                            node: item,
                            onRestore: _restore,
                            onPurge: _purge,
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

String _recycledAtLabel(FileNode node) {
  final recycledAt = node.recycledAt;
  return recycledAt == null ? '已删除' : formatDateTime(recycledAt);
}

String _autoDeleteLabel(FileNode node) {
  final recycledAt = node.recycledAt;
  if (recycledAt == null) {
    return '${_recycleBinRetention.inDays} 天后自动删除';
  }
  final expiresAt = recycledAt.add(_recycleBinRetention);
  final remaining = expiresAt.difference(DateTime.now());
  if (remaining.inSeconds <= 0) {
    return '0 天后自动删除';
  }
  final daysLeft = (remaining.inHours / Duration.hoursPerDay).ceil();
  return '${daysLeft.clamp(1, _recycleBinRetention.inDays)} 天后自动删除';
}

class _RecycleActions extends StatelessWidget {
  const _RecycleActions({
    required this.node,
    required this.onRestore,
    required this.onPurge,
  });

  final FileNode node;
  final ValueChanged<FileNode> onRestore;
  final ValueChanged<FileNode> onPurge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '恢复',
          onPressed: () => onRestore(node),
          icon: Icon(Icons.restore, color: colorScheme.primary),
        ),
        IconButton(
          tooltip: '彻底删除',
          onPressed: () => onPurge(node),
          icon: Icon(Icons.delete_outline, color: colorScheme.error),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text('回收站为空')),
    );
  }
}
