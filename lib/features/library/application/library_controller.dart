import 'package:flutter/foundation.dart';

import '../data/podcast_repository.dart';
import '../domain/podcast.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(this._repository);

  static const maxSubscriptions = 10;

  final PodcastRepository _repository;
  List<Podcast> podcasts = const [];
  bool isLoading = false;
  bool isRefreshing = false;
  String? errorMessage;

  bool get canAdd => podcasts.length < maxSubscriptions;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      podcasts = await _repository.listSubscriptions();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> add(String feedUrl) async {
    if (!canAdd) {
      throw const PodcastRepositoryException('最多只能收藏 10 个播客');
    }
    final podcast = await _repository.addSubscription(feedUrl);
    podcasts = [...podcasts, podcast]
      ..sort((left, right) => left.title.compareTo(right.title));
    notifyListeners();
  }

  Future<void> delete(int podcastId) async {
    await _repository.deleteSubscription(podcastId);
    podcasts = podcasts.where((podcast) => podcast.id != podcastId).toList();
    notifyListeners();
  }

  Future<RefreshResult> refresh() async {
    isRefreshing = true;
    notifyListeners();
    try {
      final result = await _repository.refreshSubscriptions();
      podcasts = await _repository.listSubscriptions();
      return result;
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<List<PodcastSearchResult>> search(String query) {
    return _repository.search(query);
  }

  Future<List<Episode>> episodes(int podcastId) {
    return _repository.listEpisodes(podcastId);
  }
}
