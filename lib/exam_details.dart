import 'package:material_ui/material_ui.dart';
import 'package:nscgschedule/models/exam_models.dart';
import 'package:nscgschedule/settings.dart';

class ExamDetailsScreen extends StatefulWidget {
  const ExamDetailsScreen({super.key});

  @override
  State<ExamDetailsScreen> createState() => _ExamDetailsScreenState();
}

class _ExamDetailsScreenState extends State<ExamDetailsScreen> {
  ExamTimetable? _examTimetable;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExamData();
  }

  // Helper function to deeply convert Map<dynamic, dynamic> to Map<String, dynamic>
  Map<String, dynamic> _convertToTypedMap(Map<dynamic, dynamic> map) {
    return Map<String, dynamic>.fromIterable(
      map.entries,
      key: (entry) => entry.key.toString(),
      value: (entry) {
        if (entry.value is Map<dynamic, dynamic>) {
          return _convertToTypedMap(entry.value);
        } else if (entry.value is List) {
          return (entry.value as List).map((item) {
            if (item is Map<dynamic, dynamic>) {
              return _convertToTypedMap(item);
            }
            return item;
          }).toList();
        }
        return entry.value;
      },
    );
  }

  Future<void> _loadExamData() async {
    final examTimetableData = await settings.getMap('examTimetable');

    if (examTimetableData.isNotEmpty) {
      try {
        final typedData = _convertToTypedMap(examTimetableData);
        final examTimetable = ExamTimetable.fromJson(typedData);
        if (mounted) {
          setState(() {
            _examTimetable = examTimetable;
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading exam timetable: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Information')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_examTimetable == null || _examTimetable!.studentInfo == null) {
      return const Center(child: Text('No student information available'));
    }

    final studentInfo = _examTimetable!.studentInfo!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Important Instructions Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.priority_high,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'IMPORTANT',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInstruction(
                    'Please bring this information with you to all your exams',
                  ),
                  _buildInstruction(
                    'WATER BOTTLES MUST NOT HAVE LABELS ON',
                    bold: true,
                  ),
                  _buildInstruction(
                    'Watches are not allowed in Exams',
                    bold: true,
                  ),
                  _buildInstruction(
                    'Before exams, please read information on the exam board requirements on i-Site in the Student Essentials section',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Student Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student Details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(context, 'Ref No.', studentInfo.refNo),
                  _buildDetailRow(context, 'Name', studentInfo.name),
                  _buildDetailRow(
                    context,
                    'Date of Birth',
                    studentInfo.dateOfBirth,
                  ),
                  _buildDetailRow(context, 'ULN', studentInfo.uln),
                  _buildDetailRow(
                    context,
                    'Candidate No.',
                    studentInfo.candidateNo,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Exam Room Instructions Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exam Room Instructions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInstruction(
                    'You must go to the room shown and sit at the specified seat. Other people taking the exam may be in different rooms. Make sure you are in the correct room.',
                  ),
                  _buildInstruction(
                    'If you have an Exam Clash or a Supervised Lunch, you must not leave the Exam Room unless you are accompanied by an Invigilator',
                  ),
                  _buildInstruction(
                    'If you have an Exam Clash and then decide not to sit one of the Papers contact the Exams Office to check your start time for the remaining exam(s)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Contact Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exam Office Contacts',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildContactRow(
                    context,
                    'Newcastle',
                    '01782 254390 or 01782 254238',
                  ),
                  _buildContactRow(context, 'Stafford', '01785 275458'),
                  const Divider(height: 24),
                  Text(
                    'Exam Centre Numbers',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildContactRow(context, 'Newcastle', '30290'),
                  _buildContactRow(context, 'Stafford', '30405'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontStyle: bold ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildContactRow(BuildContext context, String location, String info) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              location,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(info)),
        ],
      ),
    );
  }
}
