import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vault_widgets.dart';
import '../../files/presentation/file_list_page.dart';

enum _TransferTab { downloads, uploads }

class TaskCenterPage extends StatefulWidget {
  const TaskCenterPage({super.key});

  @override
  State<TaskCenterPage> createState() => _TaskCenterPageState();
}

class _TaskCenterPageState extends State<TaskCenterPage> {
  static const _activeRefreshInterval = Duration(seconds: 1);

  _TransferTab _selectedTab = _TransferTab.downloads;
  List<TransferTaskInfo> _tasks = const [];
  String? _errorMessage;
  bool _connectionFailure = false;
  bool _pendingConnectionFailureNotice = false;
  bool _initialized = false;
  bool _loadingInitial = true;
  bool _refreshing = false;
  TransferTaskEvents? _transferTaskEvents;
  int _lastSeenEventVersion = 0;
  int _reloadGeneration = 0;
  Timer? _activeRefreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = DependenciesScope.of(context);
    if (_transferTaskEvents != dependencies.transferTaskEvents) {
      _transferTaskEvents?.removeListener(_handleTransferTasksChanged);
      _transferTaskEvents = dependencies.transferTaskEvents;
      _lastSeenEventVersion = dependencies.transferTaskEvents.version;
      _transferTaskEvents?.addListener(_handleTransferTasksChanged);
    }
    if (!_initialized) {
      _initialized = true;
      _reload(showLoading: true, force: true);
    }
  }

  @override
  void dispose() {
    _activeRefreshTimer?.cancel();
    _transferTaskEvents?.removeListener(_handleTransferTasksChanged);
    super.dispose();
  }

  TransferDirection get _direction => _selectedTab == _TransferTab.downloads
      ? TransferDirection.download
      : TransferDirection.upload;

  Future<PageResult<TransferTaskInfo>> _load(TransferDirection direction) {
    return DependenciesScope.of(
      context,
    ).apiClient.transferTasks(direction: direction);
  }

  Future<void> _reload({bool showLoading = false, bool force = false}) async {
    final generation = ++_reloadGeneration;
    final requestedDirection = _direction;
    setState(() {
      _refreshing = true;
      if (showLoading) {
        _loadingInitial = true;
      }
    });

    try {
      final result = await _load(requestedDirection);
      if (!mounted ||
          generation != _reloadGeneration ||
          requestedDirection != _direction) {
        return;
      }
      final nextTasks = result.items;
      final changed = force || !_sameTasks(_tasks, nextTasks);
      setState(() {
        if (changed) {
          _tasks = nextTasks;
        }
        _errorMessage = null;
        _connectionFailure = false;
        _pendingConnectionFailureNotice = false;
        _loadingInitial = false;
        _refreshing = false;
      });
      _updateActiveRefreshTimer();
    } catch (error) {
      if (!mounted ||
          generation != _reloadGeneration ||
          requestedDirection != _direction) {
        return;
      }
      final connectionFailure = isNetworkConnectionFailure(error);
      setState(() {
        if (connectionFailure) {
          _tasks = const [];
        }
        _errorMessage = connectionFailure
            ? null
            : normalizeApiError(error).message;
        _connectionFailure = connectionFailure;
        _pendingConnectionFailureNotice = connectionFailure;
        _loadingInitial = false;
        _refreshing = false;
      });
      if (!connectionFailure && _tasks.isNotEmpty) {
        _showError(error);
      }
      _updateActiveRefreshTimer();
    }
  }

  void _handleTransferTasksChanged() {
    final events = _transferTaskEvents;
    if (events == null || events.version == _lastSeenEventVersion) {
      return;
    }
    _lastSeenEventVersion = events.version;
    _reload();
  }

  void _updateActiveRefreshTimer() {
    final shouldPoll = _tasks.any(_isLiveTask);
    if (!shouldPoll) {
      _activeRefreshTimer?.cancel();
      _activeRefreshTimer = null;
      return;
    }
    if (_activeRefreshTimer != null) {
      return;
    }
    _activeRefreshTimer = Timer.periodic(_activeRefreshInterval, (_) {
      if (!mounted || _refreshing) {
        return;
      }
      _reload();
    });
  }

  bool _isLiveTask(TransferTaskInfo task) {
    return task.status == TransferTaskStatus.waiting ||
        task.status == TransferTaskStatus.active ||
        task.status == TransferTaskStatus.paused;
  }

  Future<void> _toggle(TransferTaskInfo task) async {
    try {
      final dependencies = DependenciesScope.of(context);
      if (task.status == TransferTaskStatus.paused) {
        unawaited(
          dependencies.transferResumeService.resume(
            task,
            onProgress: (_) => dependencies.transferTaskEvents.markChanged(),
          ).catchError((Object error) {
            if (mounted) {
              _showError(error);
            }
          }),
        );
      } else {
        await dependencies.transferResumeService.pause(task);
      }
      if (mounted) {
        await _reload(force: true);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _pauseAllTasks() async {
    try {
      final dependencies = DependenciesScope.of(context);
      for (final task in _tasks.where(_isLiveTask)) {
        if (task.status != TransferTaskStatus.paused) {
          await dependencies.transferResumeService.pause(task);
        }
      }
      await _reload(force: true);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _resumeAllTasks() async {
    try {
      final dependencies = DependenciesScope.of(context);
      for (final task in _tasks) {
        if (task.status == TransferTaskStatus.paused) {
          unawaited(
            dependencies.transferResumeService.resume(
              task,
              onProgress: (_) => dependencies.transferTaskEvents.markChanged(),
            ).catchError((Object error) {
              if (mounted) {
                _showError(error);
              }
            }),
          );
        }
      }
      await _reload(force: true);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _clearTasks() async {
    final confirmed = await _confirm(
      title: '清空传输记录',
      message: '要清空当前列表中的全部记录吗？正在进行的传输会立即中断。',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      final dependencies = DependenciesScope.of(context);
      await dependencies.transferResumeService.clear(_tasks, _direction);
      if (mounted) {
        setState(() {
          _tasks = const [];
        });
        await _reload(force: true);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteTask(TransferTaskInfo task) async {
    final confirmed = await _confirm(
      title: '删除传输记录',
      message: '要删除这条传输记录吗？正在进行的传输会立即中断。',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await DependenciesScope.of(context).transferResumeService.delete(task);
      if (mounted) {
        setState(() {
          _tasks = _tasks.where((item) => item.id != task.id).toList();
        });
        await _reload(force: true);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return showAppConfirmation(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    showAppNotice(
      context,
      normalizeApiError(error).message,
      type: AppNoticeType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '传输',
      currentRoute: AppRoute.tasks,
      body: FixedSimplePage(
        header: PageIntro(
          title: '任务中心',
          leadingIcon: Icons.sync_alt,
          trailing: _TaskCenterHeaderActions(
            onPauseAll: _pauseAllTasks,
            onResumeAll: _resumeAllTasks,
            onClear: _clearTasks,
          ),
        ),
        expandedChild: _TasksPanel(
          title: _selectedTab == _TransferTab.downloads ? '下载任务' : '上传任务',
          items: _tasks,
          errorMessage: _errorMessage,
          showConnectionFailureNotice: _pendingConnectionFailureNotice,
          showEmptyState:
              !_loadingInitial && !_connectionFailure && _errorMessage == null,
          onConnectionFailureNoticeShown: () {
            if (!mounted || !_pendingConnectionFailureNotice) {
              return;
            }
            setState(() {
              _pendingConnectionFailureNotice = false;
            });
          },
          onToggle: _toggle,
          onDelete: _deleteTask,
        ),
        children: [
          _TaskActions(
            selectedTab: _selectedTab,
            onSelected: (tab) {
              _activeRefreshTimer?.cancel();
              _activeRefreshTimer = null;
              setState(() {
                _selectedTab = tab;
                _errorMessage = null;
                _connectionFailure = false;
                _pendingConnectionFailureNotice = false;
                _loadingInitial = true;
              });
              _reload(showLoading: true, force: true);
            },
          ),
        ],
      ),
    );
  }
}

class _TaskCenterHeaderActions extends StatelessWidget {
  const _TaskCenterHeaderActions({
    required this.onPauseAll,
    required this.onResumeAll,
    required this.onClear,
  });

  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    if (isCompact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '全部暂停',
            onPressed: onPauseAll,
            icon: const Icon(Icons.pause_circle_outline),
          ),
          IconButton(
            tooltip: '全部继续',
            onPressed: onResumeAll,
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: onClear,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: onPauseAll,
          icon: const Icon(Icons.pause_circle_outline),
          label: const Text('全部暂停'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onResumeAll,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('全部继续'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空'),
        ),
      ],
    );
  }
}

bool _sameTasks(List<TransferTaskInfo> current, List<TransferTaskInfo> next) {
  if (current.length != next.length) {
    return false;
  }
  for (var index = 0; index < current.length; index++) {
    if (_taskSignature(current[index]) != _taskSignature(next[index])) {
      return false;
    }
  }
  return true;
}

String _taskSignature(TransferTaskInfo task) {
  return [
    task.id,
    task.direction.name,
    task.taskType,
    task.sourceId,
    task.title,
    task.totalBytes,
    task.transferredBytes,
    task.progress,
    task.status.name,
    userFacingErrorMessage(task.failureReason ?? '', fallback: ''),
    task.updatedAt.toIso8601String(),
    task.completedAt?.toIso8601String() ?? '',
  ].join('|');
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({required this.selectedTab, required this.onSelected});

  final _TransferTab selectedTab;
  final ValueChanged<_TransferTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TransferTab>(
      segments: const [
        ButtonSegment(
          value: _TransferTab.downloads,
          icon: Icon(Icons.download_outlined),
          label: Text('下载'),
        ),
        ButtonSegment(
          value: _TransferTab.uploads,
          icon: Icon(Icons.upload_file),
          label: Text('上传'),
        ),
      ],
      selected: {selectedTab},
      onSelectionChanged: (selection) => onSelected(selection.first),
    );
  }
}

class _TasksPanel extends StatelessWidget {
  const _TasksPanel({
    required this.title,
    required this.items,
    required this.errorMessage,
    required this.showConnectionFailureNotice,
    required this.showEmptyState,
    required this.onConnectionFailureNoticeShown,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final List<TransferTaskInfo> items;
  final String? errorMessage;
  final bool showConnectionFailureNotice;
  final bool showEmptyState;
  final VoidCallback onConnectionFailureNoticeShown;
  final ValueChanged<TransferTaskInfo> onToggle;
  final ValueChanged<TransferTaskInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    if (showConnectionFailureNotice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showNetworkConnectionFailureSnackBar(context);
        onConnectionFailureNoticeShown();
      });
    }

    return SimplePanel(
      title: title,
      expandChild: true,
      child: items.isEmpty && showEmptyState
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('暂无任务')),
            )
          : Column(
              children: [
                if (errorMessage != null) ...[
                  Text(
                    errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: ListView.separated(
                    primary: false,
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SectionDivider(),
                    itemBuilder: (context, index) => _TaskRow(
                      task: items[index],
                      onToggle: onToggle,
                      onDelete: onDelete,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final TransferTaskInfo task;
  final ValueChanged<TransferTaskInfo> onToggle;
  final ValueChanged<TransferTaskInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (task.status) {
      TransferTaskStatus.active ||
      TransferTaskStatus.waiting => const Color(0xFF2563EB),
      TransferTaskStatus.paused => colorScheme.outline,
      TransferTaskStatus.done => const Color(0xFF16A34A),
      TransferTaskStatus.failed ||
      TransferTaskStatus.canceled => colorScheme.error,
    };
    final progress = task.progress.clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SimpleListRow(
            icon: task.taskType == 'folder'
                ? Icons.folder_outlined
                : Icons.description_outlined,
            title: task.title,
            subtitle: '${formatBytes(task.totalBytes)} · ${_statusLabel(task)}',
            trailing: _TaskRowActions(
              task: task,
              onToggle: onToggle,
              onDelete: onDelete,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(TransferTaskInfo task) {
    return switch (task.status) {
      TransferTaskStatus.waiting => '等待中',
      TransferTaskStatus.active => '传输中',
      TransferTaskStatus.paused => '已暂停',
      TransferTaskStatus.done => '已完成',
      TransferTaskStatus.failed => userFacingErrorMessage(
        task.failureReason,
        fallback: '失败',
      ),
      TransferTaskStatus.canceled => '已取消',
    };
  }
}

class _TaskControlAction extends StatelessWidget {
  const _TaskControlAction({required this.task, required this.onToggle});

  final TransferTaskInfo task;
  final ValueChanged<TransferTaskInfo> onToggle;

  @override
  Widget build(BuildContext context) {
    if (task.status == TransferTaskStatus.done ||
        task.status == TransferTaskStatus.failed ||
        task.status == TransferTaskStatus.canceled) {
      return const SizedBox(width: 48, height: 48);
    }

    final isActive = task.status != TransferTaskStatus.paused;

    return IconButton(
      tooltip: isActive ? '暂停' : '继续',
      onPressed: () => onToggle(task),
      icon: Icon(
        isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
      ),
    );
  }
}

class _TaskRowActions extends StatelessWidget {
  const _TaskRowActions({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final TransferTaskInfo task;
  final ValueChanged<TransferTaskInfo> onToggle;
  final ValueChanged<TransferTaskInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canToggle(task))
          _TaskControlAction(task: task, onToggle: onToggle),
        IconButton(
          tooltip: '删除记录',
          onPressed: () => onDelete(task),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  bool _canToggle(TransferTaskInfo task) {
    return task.status == TransferTaskStatus.waiting ||
        task.status == TransferTaskStatus.active ||
        task.status == TransferTaskStatus.paused;
  }
}

