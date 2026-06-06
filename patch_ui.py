import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('lib/check_in_out_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ─────────────────────────────────────────────────────────────────────────────
# 1. Sticky header: replace return RefreshIndicator( opening
#    → return Column( with fixed logo header on top
# ─────────────────────────────────────────────────────────────────────────────
old1 = """        return RefreshIndicator(
          onRefresh: () async {
            await fetchShifts();
            await fetchStatus();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 90,"""

new1 = """        return Column(
          children: [
            // Fixed header — stays visible while body scrolls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 68,"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('step1 ok: sticky header opening')
else:
    print('step1 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 2. After greeting, transition to Expanded scrollable section
#    Also reduce greeting font 18→15 and date font 16→13
# ─────────────────────────────────────────────────────────────────────────────
old2 = """            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${_getGreetingMessage()} : ',
                      style: const TextStyle(
                        color: Color(0xFF039C0D),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: widget.empName.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0C0D0C),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              today,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),"""

new2 = r"""            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${_getGreetingMessage()} : ',
                      style: const TextStyle(
                        color: Color(0xFF039C0D),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: widget.empName.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0C0D0C),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              today,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 8, thickness: 0.5, indent: 16, endIndent: 16),
            // ── Scrollable body ────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await fetchShifts();
                  await fetchStatus();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                  children: [
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),"""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('step2 ok: opened Expanded section + reduced fonts')
else:
    print('step2 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 3. SizedBox(height: 20) between shift selector and buttons
#    + move working hours ABOVE buttons
#    + reduce button sizes
# ─────────────────────────────────────────────────────────────────────────────
old3 = """            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckIn &&
                                  !isProcessing &&
                                  selectedShift != null &&
                                  empShifts.any(
                                    (shift) =>
                                        shift['id'] == selectedShift &&
                                        shift['isActive'] as bool,
                                  ))
                              ? () async {
                                final selectedShiftData = empShifts.firstWhere(
                                  (shift) => shift['id'] == selectedShift,
                                  orElse: () => {'isActive': false},
                                );
                                if (selectedShiftData['isActive'] as bool) {
                                  await handleCheckIn();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select an active shift.',
                                      ),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckIn &&
                                    !isProcessing &&
                                    selectedShift != null &&
                                    empShifts.any(
                                      (shift) =>
                                          shift['id'] == selectedShift &&
                                          shift['isActive'] as bool,
                                    ))
                                ? 1.0
                                : 0.4,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1AEA24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Icon(
                                Icons.login,
                                size: 36,
                                color: Colors.black,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                checkInTime,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Check In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),"""

new3 = """            const SizedBox(height: 8),
            // Total working hours — shown above buttons
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Shifts Working Time: $totalWorkingHours',
                style: const TextStyle(color: Color(0xFF121111), fontSize: 14),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckIn &&
                                  !isProcessing &&
                                  selectedShift != null &&
                                  empShifts.any(
                                    (shift) =>
                                        shift['id'] == selectedShift &&
                                        shift['isActive'] as bool,
                                  ))
                              ? () async {
                                final selectedShiftData = empShifts.firstWhere(
                                  (shift) => shift['id'] == selectedShift,
                                  orElse: () => {'isActive': false},
                                );
                                if (selectedShiftData['isActive'] as bool) {
                                  await handleCheckIn();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select an active shift.',
                                      ),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckIn &&
                                    !isProcessing &&
                                    selectedShift != null &&
                                    empShifts.any(
                                      (shift) =>
                                          shift['id'] == selectedShift &&
                                          shift['isActive'] as bool,
                                    ))
                                ? 1.0
                                : 0.4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1AEA24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Icon(
                                Icons.login,
                                size: 28,
                                color: Colors.black,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                checkInTime,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(
                                'Check In',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),"""

if old3 in content:
    content = content.replace(old3, new3, 1)
    print('step3 ok: working hours moved up, buttons smaller')
else:
    print('step3 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 4. Reduce check-OUT button size too + remove old working hours text position
# ─────────────────────────────────────────────────────────────────────────────
old4 = """                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckOut && !isProcessing)
                              ? () async {
                                await handleCheckOut();
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckOut && !isProcessing) ? 1.0 : 0.4,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Icon(
                                Icons.logout,
                                size: 36,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                checkOutTime,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Check Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),"""

new4 = """                  Expanded(
                    child: GestureDetector(
                      onTap:
                          (isAllowedToCheckOut && !isProcessing)
                              ? () async {
                                await handleCheckOut();
                              }
                              : null,
                      child: Opacity(
                        opacity:
                            (isAllowedToCheckOut && !isProcessing) ? 1.0 : 0.4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Icon(
                                Icons.logout,
                                size: 28,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                checkOutTime,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(
                                'Check Out',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),"""

if old4 in content:
    content = content.replace(old4, new4, 1)
    print('step4 ok: check-out button smaller')
else:
    print('step4 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 5. Remove OLD working hours position (it was after buttons, now moved up)
#    + reduce the SizedBox before calendar
# ─────────────────────────────────────────────────────────────────────────────
old5 = """            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Shifts Working Time: $totalWorkingHours',
                style: const TextStyle(color: Color(0xFF121111), fontSize: 16),
              ),
            ),
            // Attendance calendar"""

new5 = """            const SizedBox(height: 10),
            // Attendance calendar"""

if old5 in content:
    content = content.replace(old5, new5, 1)
    print('step5 ok: removed old working hours position')
else:
    print('step5 FAILED')

# ─────────────────────────────────────────────────────────────────────────────
# 6. Fix the closing braces of the return statement
#    Old: ]), ), ); }   (3-level close)
#    New: ]), ), ), ), ), ], );  (5-level close for Expanded wrapper)
# ─────────────────────────────────────────────────────────────────────────────
old6 = """            const SizedBox(height: 24),
          ],
        ),
      ),
      );
      }
      switch (index) {"""

new6 = """            const SizedBox(height: 24),
                  ],
                  ),
                ),
              ),
            ),
          ],
        );
      }
      switch (index) {"""

if old6 in content:
    content = content.replace(old6, new6, 1)
    print('step6 ok: fixed closing braces')
else:
    print('step6 FAILED')
    idx = content.find('switch (index) {')
    print(repr(content[idx-200:idx+20]))

with open('lib/check_in_out_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('main screen patches saved')
