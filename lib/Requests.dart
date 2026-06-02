import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'services/api_service.dart';

class Requests extends StatefulWidget {
  final String empId;
  final String empName;
  final String authToken;
  final String deviceSerialNumber;
  final String companyId;

  const Requests({
    super.key,
    required this.empId,
    required this.empName,
    required this.authToken,
    required this.deviceSerialNumber,
    required this.companyId,
  });

  @override
  State<Requests> createState() => _RequestsState();
}

class _RequestsState extends State<Requests> {
  List<ApiTask> projects = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchTasks();
  }

  Future<void> fetchTasks() async {
    try {
      final res = await ApiService.fetchTasks(
        authToken: widget.authToken,
      );

      final data = jsonDecode(res.body);

      if (data["status"] == "success") {
        setState(() {
          projects = (data["tasks"] as List)
              .map((e) => ApiTask.fromJson(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // ── CURVED GRADIENT HEADER ─────────────────────────────────
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.teal.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              right: 20,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                const Text(
                  'My Tasks',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── BODY CONTENTS ──────────────────────────────────────────
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : projects.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.assignment_turned_in_rounded,
                              size: 80,
                              color: Colors.teal,
                            ),
                            SizedBox(height: 20),
                            Text(
                              "No tasks found",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: projects.length,
                        itemBuilder: (context, index) {
                          final project = projects[index];

                          // Dynamic gradient selection based on index to add "More UI Color"!
                          final gradients = [
                            [Colors.teal.shade500, Colors.green.shade400],
                            [Colors.blue.shade500, Colors.teal.shade400],
                            [Colors.green.shade600, Colors.teal.shade500],
                            [Colors.teal.shade600, Colors.cyan.shade500],
                          ];
                          final gradient = gradients[index % gradients.length];

                          final initials = project.projectName.isNotEmpty
                              ? project.projectName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                              : 'TS';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  // Left teal border strip
                                  Container(
                                    width: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade600,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        bottomLeft: Radius.circular(16),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SubProjectScreen(
                                              task: project,
                                              authToken: widget.authToken,
                                            ),
                                          ),
                                        );
                                      },
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(16),
                                        bottomRight: Radius.circular(16),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            // Colorful Gradient Project Initial Avatar!
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: gradient,
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                initials,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    project.projectName.toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Color(0xFF1E293B),
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    project.taskName,
                                                    style: TextStyle(
                                                      color: Colors.grey.shade600,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  // Colorful Detail Badges!
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: project.subprojects.isNotEmpty
                                                              ? Colors.teal.shade50
                                                              : Colors.orange.shade50,
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment.centerLeft,
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                project.subprojects.isNotEmpty
                                                                    ? Icons.account_tree_rounded
                                                                    : Icons.warning_amber_rounded,
                                                                size: 14,
                                                                color: project.subprojects.isNotEmpty
                                                                    ? Colors.teal.shade700
                                                                    : Colors.orange.shade800,
                                                              ),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                project.subprojects.isNotEmpty
                                                                    ? '${project.subprojects.length} Subprojects'
                                                                    : 'No Subprojects',
                                                                style: TextStyle(
                                                                  color: project.subprojects.isNotEmpty
                                                                      ? Colors.teal.shade700
                                                                      : Colors.orange.shade800,
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: Colors.teal.shade600,
                                              size: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ================= SUBPROJECT SCREEN =================

class SubProjectScreen extends StatefulWidget {
  final ApiTask task;
  final String authToken;

  const SubProjectScreen({
    super.key,
    required this.task,
    required this.authToken,
  });

  @override
  State<SubProjectScreen> createState() => _SubProjectScreenState();
}

class _SubProjectScreenState extends State<SubProjectScreen> {
  String? selectedSubproject;
  int hours = 0;
  final TextEditingController desc = TextEditingController();
  PlatformFile? pickedFile;
  bool isLoading = false;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null && mounted) {
      setState(() {
        pickedFile = result.files.first;
      });
    }
  }

  Future<void> submitReport() async {
    if ((widget.task.subprojects.isNotEmpty && selectedSubproject == null) ||
        hours == 0 ||
        desc.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final reportDate = DateTime.now().toString().split(" ")[0];

      var response = await ApiService.submitTaskReport(
        authToken: widget.authToken,
        taskId: widget.task.taskId.toString(),
        subproject: selectedSubproject ?? "",
        reportDate: reportDate,
        reportTime: hours.toString(),
        description: desc.text,
        filePath: (pickedFile != null && pickedFile!.path != null) ? pickedFile!.path! : null,
      );
      var responseBody = await response.stream.bytesToString();
      final data = jsonDecode(responseBody);

      if (!mounted) return;

      if (response.statusCode == 200 && data["status"] == "success") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Report Submitted"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data["message"] ?? "Submission failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Something went wrong"),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    desc.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
      prefixIcon: Icon(prefixIcon, color: Colors.teal.shade700),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
      ),
    );
  }

  Widget buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 6,
            color: Colors.black12,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // ── CURVED GRADIENT HEADER ─────────────────────────────────
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.teal.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              right: 20,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Submit Task Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── SCROLLABLE FORM ────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  buildCard(
                    child: widget.task.subprojects.isEmpty
                        ? const Text(
                            "No Subprojects Available",
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.red,
                                fontWeight: FontWeight.w500),
                          )
                        : DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: _buildInputDecoration(
                              labelText: "Select Subproject",
                              prefixIcon: Icons.account_tree_rounded,
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            items: widget.task.subprojects.map((sub) {
                              return DropdownMenuItem(
                                value: sub,
                                child: Text(sub, style: const TextStyle(color: Colors.black87)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                selectedSubproject = val;
                              });
                            },
                          ),
                  ),

                  buildCard(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: _buildInputDecoration(
                        labelText: "Select Hours",
                        prefixIcon: Icons.hourglass_bottom_rounded,
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      items: List.generate(8, (i) => i + 1).map((h) {
                        return DropdownMenuItem(
                          value: h,
                          child: Text("$h Hours", style: const TextStyle(color: Colors.black87)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            hours = val;
                          });
                        }
                      },
                    ),
                  ),

                  buildCard(
                    child: TextField(
                      controller: desc,
                      maxLines: 4,
                      decoration: _buildInputDecoration(
                        labelText: "Work Description",
                        prefixIcon: Icons.notes_rounded,
                      ),
                    ),
                  ),

                  buildCard(
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade600,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: pickFile,
                          icon: const Icon(Icons.attach_file_rounded),
                          label: const Text("Attach File", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (pickedFile != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    pickedFile!.name,
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: submitReport,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                elevation: 4,
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.green.shade700, Colors.teal.shade500],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Container(
                                  height: 52,
                                  alignment: Alignment.center,
                                  child: const Text(
                                    "Submit Report",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= MODEL =================

class ApiTask {
  final int taskId;
  final String projectName;
  final String taskName;
  final List<String> subprojects;

  ApiTask({
    required this.taskId,
    required this.projectName,
    required this.taskName,
    required this.subprojects,
  });

  factory ApiTask.fromJson(Map<String, dynamic> json) {
    return ApiTask(
      taskId: int.parse(json["task_id"].toString()),
      projectName: json["project_name"] ?? "",
      taskName: json["task_name"] ?? "",
      subprojects: List<String>.from(json["subprojects"] ?? []),
    );
  }
}