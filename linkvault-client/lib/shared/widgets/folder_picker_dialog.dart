import 'package:flutter/material.dart';

import '../../core/network/linkvault_models.dart';
import 'app_feedback.dart';
import 'vault_widgets.dart';

const folderPickerRootTargetId = '__root__';

String? folderPickerTargetToParentId(String targetId) {
  return targetId == folderPickerRootTargetId ? null : targetId;
}

Future<String?> showFolderPickerDialog(
  BuildContext context, {
  required String title,
  required Future<PageResult<FileNode>> Function(String? parentId) loadFolders,
  Set<String> excludedFolderIds = const <String>{},
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => FolderPickerDialog(
      title: title,
      excludedFolderIds: excludedFolderIds,
      loadFolders: loadFolders,
    ),
  );
}

class FolderPickerDialog extends StatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.title,
    required this.loadFolders,
    this.excludedFolderIds = const <String>{},
  });

  final String title;
  final Set<String> excludedFolderIds;
  final Future<PageResult<FileNode>> Function(String? parentId) loadFolders;

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  final List<_PickerFolderCrumb> _path = [
    const _PickerFolderCrumb(id: folderPickerRootTargetId, name: '根目录'),
  ];
  late Future<PageResult<FileNode>> _future;

  String? get _currentParentId {
    final id = _path.last.id;
    return id == folderPickerRootTargetId ? null : id;
  }

  @override
  void initState() {
    super.initState();
    _future = widget.loadFolders(_currentParentId);
  }

  void _openFolder(FileNode folder) {
    setState(() {
      _path.add(_PickerFolderCrumb(id: folder.id, name: folder.name));
      _future = widget.loadFolders(_currentParentId);
    });
  }

  void _goTo(int index) {
    setState(() {
      _path.removeRange(index + 1, _path.length);
      _future = widget.loadFolders(_currentParentId);
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_path.last.id);
  }

  @override
  Widget build(BuildContext context) {
    final pickerHeight = (MediaQuery.sizeOf(context).height * 0.56).clamp(
      280.0,
      420.0,
    );

    return AlertDialog(
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          widget.title,
          style: Theme.of(context).dialogTheme.titleTextStyle?.copyWith(
            fontSize: 20,
          ),
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: pickerHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PickerFolderBreadcrumb(path: _path, onSelected: _goTo),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<PageResult<FileNode>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Text('正在加载文件夹'));
                  }
                  final connectionFailure =
                      snapshot.hasError &&
                      isNetworkConnectionFailure(snapshot.error!);
                  if (connectionFailure) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      showNetworkConnectionFailureSnackBar(context);
                    });
                  }
                  final folders =
                      (snapshot.hasError
                              ? const <FileNode>[]
                              : snapshot.data?.items ?? const <FileNode>[])
                          .where(
                            (folder) =>
                                !widget.excludedFolderIds.contains(folder.id),
                      )
                      .toList();
                  if (folders.isEmpty && !snapshot.hasError) {
                    return const Center(child: Text('当前文件夹下没有文件夹'));
                  }
                  return ListView.separated(
                    itemCount: folders.length,
                    separatorBuilder: (context, index) =>
                        const SectionDivider(),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return SimpleListRow(
                        dense: true,
                        icon: Icons.folder_outlined,
                        title: folder.name,
                        subtitle: _formatDateTime(folder.updatedAt),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openFolder(folder),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('选择')),
      ],
    );
  }
}

class _PickerFolderBreadcrumb extends StatefulWidget {
  const _PickerFolderBreadcrumb({
    required this.path,
    required this.onSelected,
  });

  final List<_PickerFolderCrumb> path;
  final ValueChanged<int> onSelected;

  @override
  State<_PickerFolderBreadcrumb> createState() =>
      _PickerFolderBreadcrumbState();
}

class _PickerFolderBreadcrumbState extends State<_PickerFolderBreadcrumb> {
  final ScrollController _controller = ScrollController();
  String? _lastSignature;
  double? _lastWidth;
  bool _pendingAlignmentUpdate = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pathTextStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontSize: 18);

    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleAlignmentUpdate(constraints.maxWidth);
        return ClipRect(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < widget.path.length; index++) ...[
                  TextButton(
                    onPressed: index == widget.path.length - 1
                        ? null
                        : () => widget.onSelected(index),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      widget.path[index].name,
                      style: pathTextStyle,
                    ),
                  ),
                  if (index != widget.path.length - 1)
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.black,
                      size: 18,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleAlignmentUpdate(double width) {
    final signature = _pickerBreadcrumbSignature(widget.path);
    if (_lastSignature == signature && _lastWidth == width) {
      return;
    }
    _lastSignature = signature;
    _lastWidth = width;
    if (_pendingAlignmentUpdate) {
      return;
    }
    _pendingAlignmentUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingAlignmentUpdate = false;
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final position = _controller.position;
      final targetOffset = position.maxScrollExtent > 0
          ? position.maxScrollExtent
          : 0.0;
      if ((_controller.offset - targetOffset).abs() < 0.5) {
        return;
      }
      _controller.jumpTo(targetOffset);
    });
  }
}

String _pickerBreadcrumbSignature(List<_PickerFolderCrumb> path) {
  return path.map((crumb) => '${crumb.id}:${crumb.name}').join('|');
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class _PickerFolderCrumb {
  const _PickerFolderCrumb({required this.id, required this.name});

  final String id;
  final String name;
}
