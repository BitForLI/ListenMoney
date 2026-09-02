import 'dart:async';

import 'package:flutter/material.dart';

import '../application/library_controller.dart';
import '../data/local_podcast_repository.dart';
import '../data/podcast_repository.dart';
import '../domain/podcast.dart';

const _recommendedSubscriptions = [
  (
    title: 'Practical AI',
    subtitle: '实用 AI · 工程与行业动态',
    feedUrl: 'https://feeds.transistor.fm/practical-ai-machine-learning-data-science-llm',
  ),
  (
    title: 'The TED AI Show',
    subtitle: 'AI 与社会 · 深度访谈',
    feedUrl: 'https://feeds.acast.com/public/shows/6758564a102e6d4448d19589',
  ),
  (
    title: 'Latent Space',
    subtitle: 'AI 工程 · 模型与开发者生态',
    feedUrl: 'https://api.substack.com/feed/podcast/1084089.rss',
  ),
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.repository,
    this.onPlayEpisode,
    this.onPodcastsChanged,
  });

  final PodcastRepository? repository;
  final void Function(Podcast podcast, Episode episode)? onPlayEpisode;
  final ValueChanged<List<Podcast>>? onPodcastsChanged;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController(
      widget.repository ?? LocalPodcastRepository(),
    )..addListener(_onChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    await _controller.load();
    _notifyPodcastsChanged();
  }

  void _notifyPodcastsChanged() {
    if (_controller.errorMessage == null) {
      widget.onPodcastsChanged?.call(List.unmodifiable(_controller.podcasts));
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _showAddSheet() async {
    if (!_controller.canAdd) {
      _showMessage('最多只能收藏 10 个播客');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddSubscriptionSheet(controller: _controller),
    );
    _notifyPodcastsChanged();
  }

  Future<void> _refresh() async {
    try {
      final result = await _controller.refresh();
      _notifyPodcastsChanged();
      if (!mounted) return;
      final message = result.failures.isEmpty
          ? '更新完成，新增 ${result.newEpisodes} 集'
          : '更新完成；${result.failures.length} 个播客失败';
      _showMessage(message);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(Podcast podcast) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏？'),
        content: Text('“${podcast.title}”及已同步的单集会从本机移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.delete(podcast.id);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          toolbarHeight: 68,
          title: Text(
            'BANK',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: '刷新订阅',
              onPressed: _controller.isRefreshing ? null : _refresh,
              icon: _controller.isRefreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: '添加播客',
              onPressed: _controller.canAdd ? _showAddSheet : null,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
          sliver: SliverList.list(
            children: [
              if (_controller.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_controller.errorMessage != null)
                _LoadError(
                  message: _controller.errorMessage!,
                  onRetry: _controller.load,
                )
              else if (_controller.podcasts.isEmpty)
                _LibraryEmptyState(onAdd: _showAddSheet)
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _controller.podcasts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 18,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    final podcast = _controller.podcasts[index];
                    return _PodcastCard(
                      podcast: podcast,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => EpisodeListScreen(
                            podcast: podcast,
                            controller: _controller,
                            onPlayEpisode: widget.onPlayEpisode,
                          ),
                        ),
                      ),
                      onDelete: () => _confirmDelete(podcast),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
        child: Column(
          children: [
            Icon(Icons.podcasts_rounded, size: 56, color: colors.primary),
            const SizedBox(height: 20),
            Text('还没有收藏播客', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '可以搜索 Apple Podcasts，或直接粘贴 RSS 地址。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加播客'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  const _PodcastCard({
    required this.podcast,
    required this.onOpen,
    required this.onDelete,
  });

  final Podcast podcast;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _Artwork(url: podcast.artworkUrl, size: constraints.maxWidth),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                podcast.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                podcast.author?.isNotEmpty == true
                    ? podcast.author!
                    : '${podcast.episodeCount} 集',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Icon(Icons.podcasts_rounded),
    );
    if (url == null || url!.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: fallback,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

class _AddSubscriptionSheet extends StatefulWidget {
  const _AddSubscriptionSheet({required this.controller});

  final LibraryController controller;

  @override
  State<_AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends State<_AddSubscriptionSheet> {
  final _searchController = TextEditingController();
  final _rssController = TextEditingController();
  List<PodcastSearchResult> _results = const [];
  bool _isSearching = false;
  bool _isAdding = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _rssController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await widget.controller.search(query);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _add(String feedUrl) async {
    if (feedUrl.trim().isEmpty || _isAdding) return;
    setState(() {
      _isAdding = true;
      _error = null;
    });
    try {
      await widget.controller.add(feedUrl.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isAdding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加播客', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text('推荐播客', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ..._recommendedSubscriptions.map(
              (podcast) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.podcasts_rounded),
                title: Text(podcast.title),
                subtitle: Text(podcast.subtitle),
                trailing: const Icon(Icons.add_circle_outline_rounded),
                onTap: _isAdding ? null : () => _add(podcast.feedUrl),
              ),
            ),
            const Divider(height: 28),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: '搜索 Apple Podcasts',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._results
                  .take(8)
                  .map(
                    (result) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _Artwork(url: result.artworkUrl, size: 48),
                      title: Text(
                        result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: result.author == null
                          ? null
                          : Text(
                              result.author!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(Icons.add_circle_outline_rounded),
                      onTap: _isAdding ? null : () => _add(result.feedUrl),
                    ),
                  ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('或'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            TextField(
              controller: _rssController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: _add,
              decoration: const InputDecoration(
                labelText: 'RSS 地址',
                hintText: 'https://example.com/feed.xml',
                prefixIcon: Icon(Icons.rss_feed_rounded),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isAdding ? null : () => _add(_rssController.text),
              child: _isAdding
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('收藏这个播客'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EpisodeListScreen extends StatefulWidget {
  const EpisodeListScreen({
    super.key,
    required this.podcast,
    required this.controller,
    this.onPlayEpisode,
  });

  final Podcast podcast;
  final LibraryController controller;
  final void Function(Podcast podcast, Episode episode)? onPlayEpisode;

  @override
  State<EpisodeListScreen> createState() => _EpisodeListScreenState();
}

class _EpisodeListScreenState extends State<EpisodeListScreen> {
  late final Future<List<Episode>> _episodes = widget.controller.episodes(
    widget.podcast.id,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.podcast.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<List<Episode>>(
        future: _episodes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final episodes = snapshot.data ?? const [];
          if (episodes.isEmpty) {
            return const Center(child: Text('这个播客暂时没有可播放的单集'));
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ShowHeader(podcast: widget.podcast)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '最新单集',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                sliver: SliverList.separated(
                  itemCount: episodes.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    return _EpisodeRow(
                      episode: episode,
                      metadata: _episodeMetadata(episode),
                      artworkUrl: widget.podcast.artworkUrl,
                      onPlay: () =>
                          widget.onPlayEpisode?.call(widget.podcast, episode),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _episodeMetadata(Episode episode) {
    final values = <String>[];
    final date = episode.publishedAt?.toLocal();
    if (date != null) values.add('${date.year}-${date.month}-${date.day}');
    final seconds = episode.durationSeconds;
    if (seconds != null) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      values.add(hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟');
    }
    return values.isEmpty ? '已同步' : values.join(' · ');
  }
}

class _ShowHeader extends StatelessWidget {
  const _ShowHeader({required this.podcast});

  final Podcast podcast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Artwork(url: podcast.artworkUrl, size: 104),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      podcast.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    if (podcast.author?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        podcast.author!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${podcast.episodeCount} 集',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (podcast.description?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              podcast.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.metadata,
    required this.artworkUrl,
    required this.onPlay,
  });

  final Episode episode;
  final String metadata;
  final String? artworkUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Artwork(url: artworkUrl, size: 62),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    metadata,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (episode.transcriptReady ||
                      episode.hasTranscriptSource) ...[
                    const SizedBox(height: 5),
                    Text(
                      episode.transcriptReady ? '文本已就绪' : '提供时间轴文本',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.more_horiz_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
