import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/caseroom_service.dart';

class DoctorCaseRoomsScreen extends ConsumerStatefulWidget {
  const DoctorCaseRoomsScreen({super.key});

  @override
  ConsumerState<DoctorCaseRoomsScreen> createState() =>
      _DoctorCaseRoomsScreenState();
}

class _DoctorCaseRoomsScreenState extends ConsumerState<DoctorCaseRoomsScreen> {
  final _postController = TextEditingController();
  bool _isLoading = false;
  List<dynamic> _caseRooms = [];
  Map<String, dynamic>? _selectedRoom;
  List<dynamic> _posts = [];

  @override
  void initState() {
    super.initState();
    _loadCaseRooms();
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  Future<void> _loadCaseRooms() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(caseRoomServiceProvider).searchCaseRooms({
        'page': 0,
        'size': 50,
        'sortBy': 'createdAt',
        'sortDir': 'DESC',
      });
      setState(() => _caseRooms = res);
    } catch (e) {
      setState(() => _caseRooms = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load case rooms: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectCaseRoom(Map<String, dynamic> room) async {
    setState(() {
      _selectedRoom = room;
      _isLoading = true;
    });

    try {
      final res = await ref
          .read(caseRoomServiceProvider)
          .getPostsForRoom(room['caseRoomId'], size: 100);
      setState(() => _posts = res);
    } catch (e) {
      setState(() => _posts = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load posts: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _createPost() {
    final text = _postController.text.trim();
    if (text.isEmpty || _selectedRoom == null) return;

    _postController.clear();

    ref.read(caseRoomServiceProvider).createPost({
      'caseRoomId': _selectedRoom!['caseRoomId'],
      'postType': 'NOTE',
      'body': text,
    }).then((post) {
      if (mounted) setState(() => _posts.add(post));
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post: ${_errorMessage(e)}')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Clinical Case Rooms',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Multi-specialty collaborative case discussions and clinical decision support.',
                      style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _selectedRoom == null
                  ? Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _caseRooms.isEmpty
                              ? const Center(
                                  child: Text('No case rooms found.'))
                              : ListView.separated(
                                  itemCount: _caseRooms.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final cr = _caseRooms[index];
                                    return ListTile(
                                      title: Text(cr['title'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      subtitle: Text(
                                          'Patient: ${cr['patientName'] ?? ''} • Priority: ${cr['priority'] ?? ''}'),
                                      trailing: Chip(
                                        label: Text(cr['status'] ?? ''),
                                        backgroundColor:
                                            AppTheme.primaryLightTeal,
                                      ),
                                      onTap: () => _selectCaseRoom(cr),
                                    );
                                  },
                                ),
                    )
                  : Card(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: AppTheme.primaryLightTeal,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, size: 20),
                                  onPressed: () =>
                                      setState(() => _selectedRoom = null),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedRoom!['title'] ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                          'Patient: ${_selectedRoom!['patientName'] ?? ''}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _posts.length,
                                    itemBuilder: (context, idx) {
                                      final post = _posts[idx];
                                      return Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      post['authorName'] ?? '',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppTheme
                                                              .primaryTeal),
                                                    ),
                                                  ),
                                                  Text(post['postedAt'] ?? '',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppTheme
                                                              .textMuted)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(post['body'] ?? ''),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _postController,
                                    decoration: const InputDecoration(
                                        hintText:
                                            'Share clinical insight or observation...'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _createPost,
                                  child: const Text('Post'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
