import 'package:html/parser.dart' show parse;

class ExamTimetable {
  final bool hasExams;
  final StudentInfo? studentInfo;
  final List<Exam> exams;
  final String? warningMessage;

  const ExamTimetable({
    required this.hasExams,
    this.studentInfo,
    required this.exams,
    this.warningMessage,
  });

  factory ExamTimetable.fromJson(Map<String, dynamic> json) {
    final student = json['studentInfo'] != null
        ? StudentInfo.fromJson(
            Map<String, dynamic>.from(json['studentInfo'] as Map),
          )
        : null;
    final rawExams = json['exams'] as List;
    final exams = rawExams
        .map(
          (examJson) =>
              Exam.fromJson(Map<String, dynamic>.from(examJson as Map)),
        )
        .toList();
    return ExamTimetable(
      hasExams: json['hasExams'] as bool,
      studentInfo: student,
      exams: exams,
      warningMessage: json['warningMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hasExams': hasExams,
      'studentInfo': studentInfo?.toJson(),
      'exams': exams.map((exam) => exam.toJson()).toList(),
      'warningMessage': warningMessage,
    };
  }

  factory ExamTimetable.fromHtml(String html) {
    final document = parse(html);

    // Check if there are no exams
    final noDataMessage = document.querySelector('h2.notice');
    if (noDataMessage != null &&
        noDataMessage.text.contains('no data about exams')) {
      return const ExamTimetable(hasExams: false, exams: []);
    }

    // Extract warning message if present
    String? warningMessage;
    final warningDiv = document.querySelector('div[style*="color:red"]');
    if (warningDiv != null) {
      final warningH2 = warningDiv.querySelector('h2');
      if (warningH2 != null) {
        warningMessage = warningH2.text.trim();
      }
    }

    // Extract student info
    StudentInfo? studentInfo;
    final studentTable = document.querySelector('table.student_ident');
    if (studentTable != null) {
      final cells = studentTable.querySelectorAll('td');
      // The student_ident table often contains 5 <td> cells (ref, name, dob, uln, candidate no).
      // Accept 5 or more to support the common markup seen in real pages.
      if (cells.length >= 5) {
        studentInfo = StudentInfo(
          refNo: cells[0].text.trim(),
          name: cells[1].text.trim(),
          dateOfBirth: cells[2].text.trim(),
          uln: cells[3].text.trim(),
          candidateNo: cells[4].text.trim(),
        );
      }
    }

    // Extract exams
    final exams = <Exam>[];
    // The main portal homepage also publishes November resits in a compact
    // four-column table, separately from the full /exams/ timetable.
    final examTables = document.querySelectorAll('table.exams, table.examtbl');
    for (final examTable in examTables) {
      for (final row in examTable.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length >= 10) {
          exams.add(
            Exam(
              date: cells[0].text.trim(),
              boardCode: cells[1].text.trim(),
              paper: cells[2].text.trim(),
              startTime: cells[3].text.trim(),
              finishTime: cells[4].text.trim(),
              subjectDescription: cells[5].text.trim(),
              preRoom: cells[6].text.trim(),
              examRoom: cells[7].text.trim(),
              seatNumber: cells[8].text.trim(),
              additional: cells[9].text.trim(),
            ),
          );
        } else if (cells.length >= 4) {
          final date = cells[2].text.trim().replaceAll('/', '-');
          exams.add(Exam(
            date: date,
            boardCode: '',
            paper: cells[1].text.trim(),
            startTime: cells[3].text.trim(),
            finishTime: '',
            subjectDescription: cells[0].text.trim(),
            preRoom: '',
            examRoom: '',
            seatNumber: '',
            additional: '',
          ));
        }
      }
    }

    return ExamTimetable(
      hasExams: exams.isNotEmpty,
      studentInfo: studentInfo,
      exams: exams,
      warningMessage: warningMessage,
    );
  }
}

class StudentInfo {
  final String refNo;
  final String name;
  final String dateOfBirth;
  final String uln;
  final String candidateNo;

  const StudentInfo({
    required this.refNo,
    required this.name,
    required this.dateOfBirth,
    required this.uln,
    required this.candidateNo,
  });

  factory StudentInfo.fromJson(Map<String, dynamic> json) {
    return StudentInfo(
      refNo: json['refNo'] as String,
      name: json['name'] as String,
      dateOfBirth: json['dateOfBirth'] as String,
      uln: json['uln'] as String,
      candidateNo: json['candidateNo'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'refNo': refNo,
      'name': name,
      'dateOfBirth': dateOfBirth,
      'uln': uln,
      'candidateNo': candidateNo,
    };
  }
}

class Exam {
  final String date;
  final String boardCode;
  final String paper;
  final String startTime;
  final String finishTime;
  final String subjectDescription;
  final String preRoom;
  final String examRoom;
  final String seatNumber;
  final String additional;

  const Exam({
    required this.date,
    required this.boardCode,
    required this.paper,
    required this.startTime,
    required this.finishTime,
    required this.subjectDescription,
    required this.preRoom,
    required this.examRoom,
    required this.seatNumber,
    required this.additional,
  });

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      date: json['date'] as String,
      boardCode: json['boardCode'] as String,
      paper: json['paper'] as String,
      startTime: json['startTime'] as String,
      finishTime: json['finishTime'] as String,
      subjectDescription: json['subjectDescription'] as String,
      preRoom: json['preRoom'] as String,
      examRoom: json['examRoom'] as String,
      seatNumber: json['seatNumber'] as String,
      additional: json['additional'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'boardCode': boardCode,
      'paper': paper,
      'startTime': startTime,
      'finishTime': finishTime,
      'subjectDescription': subjectDescription,
      'preRoom': preRoom,
      'examRoom': examRoom,
      'seatNumber': seatNumber,
      'additional': additional,
    };
  }

  DateTime? get parsedDate {
    try {
      // Accept dates from both portal formats: 04-11-2025 and 04/11/2025.
      final parts = date.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]), // year
          int.parse(parts[1]), // month
          int.parse(parts[0]), // day
        );
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
