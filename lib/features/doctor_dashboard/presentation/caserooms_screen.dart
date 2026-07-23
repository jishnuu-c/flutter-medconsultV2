import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/caseroom_service.dart';

class DoctorCaseRoomsScreen extends ConsumerStatefulWidget {
  const DoctorCaseRoomsScreen({super.key});

  @override
  ConsumerState<DoctorCaseRoomsScreen> createState() => _DoctorCaseRoomsScreenState();
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

  Future<void> _loadCaseRooms() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(caseRoomServiceProvider).searchCaseRooms({});
      setState(() => _caseRooms = res);
    } catch (_) {
      _populateMockCaseRooms();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockCaseRooms() {
    _caseRooms = [
      {
        'caseRoomId': 'cr-101',
        'title': 'Complex Cardiac Case Review - Patient 409',
        'specialty': 'Cardiology',
        'status': 'OPEN',
        'doctorCount': 4,
        'lastPost': 'New ECG results uploaded for review.',
      },
      {
        'caseRoomId': 'cr-102',
        'title': 'Pediatric Respiratory Consultation',
        'specialty': 'Pediatrics',
        'status': 'OPEN',
        'doctorCount': 3,
        'lastPost': 'Treatment plan confirmed by Dr. Tariq.',
      },
    ];
  }

  Future<void> _selectCaseRoom(Map<String, dynamic> room) async {
    setState(() {
      _selectedRoom = room;
      _isLoading = true;
    });

    try {
      final res = await ref.read(caseRoomServiceProvider).getPostsForRoom(room['caseRoomId']);
      setState(() => _posts = res);
    } catch (_) {
      setState(() {
        _posts = [
          {
            'authorName': 'Dr. Tariq Al-Mansoor',
            'role': 'Cardiologist',
            'content': 'Patient shows ST elevation in lead II and III. Requesting second opinion on catheterization protocol.',
            'createdAt': '2 hours ago',
          },
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _createPost() {
    final text = _postController.text.trim();
    if (text.isEmpty || _selectedRoom == null) return;

    setState(() {
      _posts.add({
        'authorName': 'Dr. Practitioner',
        'role': 'Consultant',
        'content': text,
        'createdAt': 'Just now',
      });
      _postController.clear();
    });

    try {
      ref.read(caseRoomServiceProvider).createPost({
        'caseRoomId': _selectedRoom!['caseRoomId'],
        'content': text,
      });
    } catch (_) {}
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
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
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
              child: Row(
                children: [
                  // Case Rooms List
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              itemCount: _caseRooms.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final cr = _caseRooms[index];
                                final isSelected = _selectedRoom?['caseRoomId'] == cr['caseRoomId'];
                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: AppTheme.primaryLightTeal,
                                  title: Text(cr['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${cr['specialty']} • ${cr['doctorCount']} Doctors'),
                                  trailing: Chip(
                                    label: Text(cr['status']),
                                    backgroundColor: AppTheme.primaryLightTeal,
                                  ),
                                  onTap: () => _selectCaseRoom(cr),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Room Posts & Discussion
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _selectedRoom == null
                          ? const Center(child: Text('Select a case room to view discussion posts.'))
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  color: AppTheme.primaryLightTeal,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedRoom!['title'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Specialty: ${_selectedRoom!['specialty']}'),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _posts.length,
                                    itemBuilder: (context, idx) {
                                      final post = _posts[idx];
                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    post['authorName'],
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                                                  ),
                                                  Text(post['createdAt'], style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(post['content']),
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
                                          decoration: const InputDecoration(hintText: 'Share clinical insight or observation...'),
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
          ],
        ),
      ),
    );
  }
}
