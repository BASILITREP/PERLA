import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../services/location_service.dart';
import 'package:google_fonts/google_fonts.dart'; // ADD THIS

// Model para sa ating attendance log
class AttendanceLog {
  final DateTime time;
  final String status; // 'Timed In' or 'Timed Out'

  AttendanceLog({required this.time, required this.status});
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.fieldEngineer,
  });

  final String title;
  final Map<String, dynamic> fieldEngineer;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  // Gamitin natin ang bagong LocationService
  final LocationService _locationService = LocationService();

  // State variables para sa attendance
  bool _isTimedIn = false;
  DateTime? _timeInTimestamp;
  final List<AttendanceLog> _attendanceLogs = [];

  // ADD THESE FOR FAB ANIMATION
  bool _isFabExpanded = false;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize FAB animation
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _locationService.stop();
    _fabAnimationController.dispose(); // Don't forget this!
    super.dispose();
  }

  // ADD THESE METHODS
  void _toggleFab() {
    setState(() {
      _isFabExpanded = !_isFabExpanded;
      if (_isFabExpanded) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

  void _showProfile() {
    _toggleFab(); // Close FAB first
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profile: ${widget.fieldEngineer['name']}'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showDTR() {
    _toggleFab(); // Close FAB first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily Time Record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Employee: ${widget.fieldEngineer['name']}'),
            const SizedBox(height: 8),
            Text('Total Logs: ${_attendanceLogs.length}'),
            const SizedBox(height: 8),
            Text('Status: ${_isTimedIn ? "Timed In" : "Timed Out"}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    _toggleFab(); // Close FAB first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Stop location service if running
              if (_isTimedIn) {
                _locationService.stop();
              }
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to login
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _toggleTimeIn() {
    setState(() {
      _isTimedIn = !_isTimedIn;
      final now = DateTime.now();

      if (_isTimedIn) {
        // --- LOGIC PARA SA TIME IN ---
        _timeInTimestamp = now;
        _attendanceLogs.insert(0, AttendanceLog(time: now, status: 'Timed In'));

        print("==============================================");
        print("Button Tapped - TIMING IN");
        print("==============================================");
        _locationService.start(widget.fieldEngineer['id']);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have successfully timed in!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // --- LOGIC PARA SA TIME OUT ---
        _timeInTimestamp = null;
        _attendanceLogs.insert(
          0,
          AttendanceLog(time: now, status: 'Timed Out'),
        );

        print("==============================================");
        print("Button Tapped - TIMING OUT");
        print("==============================================");
        _locationService.stop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have successfully timed out.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }
  // ============== WALA NANG IBANG HANDLE TIME IN/OUT FUNCTION ==============

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DOROTI',
              style: GoogleFonts.libreBaskerville(
                fontSize: 25,
                fontWeight: FontWeight.w300, // Light weight
                fontStyle: FontStyle.italic,
                color: const Color.fromARGB(255, 246, 255, 168), // Yellow accent
              ),
              textAlign: TextAlign.center,
            ),
            CircleAvatar(
              backgroundImage:  AssetImage('assets/profile.jpg')
                      as ImageProvider,
              radius: 20,
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),
                Card(
                  elevation: 4,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      children: [
                        if (_isTimedIn && _timeInTimestamp != null)
                          _buildStatusDisplay(
                            'You are currently timed in since:',
                            DateFormat('hh:mm a').format(_timeInTimestamp!),
                            Colors.orangeAccent,
                          )
                        else
                          _buildStatusDisplay(
                            'You are currently timed out.',
                            'Press button to time in.',
                            Colors.grey[600]!,
                          ),
                
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // MATERIAL 3 SEGMENTED BUTTON
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(100),
                  ),

                  child: Row(
                  
                    children: [
                      // TIME IN BUTTON
                      Expanded(
                        
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: !_isTimedIn ? _toggleTimeIn : null,
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: !_isTimedIn
                                    ? colorScheme
                                          .primary // Active - Yellow
                                    : Colors.transparent, // Inactive
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.login,
                                    color: !_isTimedIn
                                        ? Colors.black87
                                        : Colors.grey[600],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Clock In',
                                    style: TextStyle(
                                      height: 1.5,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: !_isTimedIn
                                          ? Colors.black87
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // TIME OUT BUTTON
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isTimedIn ? _toggleTimeIn : null,
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: _isTimedIn
                                    ? Colors
                                          .orange[600] // Active - Orange for time out
                                    : Colors.transparent, // Inactive
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: _isTimedIn
                                        ? Colors.white
                                        : Colors.grey[600],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Clock Out',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _isTimedIn
                                          ? Colors.white
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                Text(
                  'Attendance Logs',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(color: Colors.white70),

                // Attendance Logs List
                Expanded(
                  child: _attendanceLogs.isEmpty
                      ? Center(
                          child: Text(
                            'No attendance logs yet.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _attendanceLogs.length,
                          itemBuilder: (context, index) {
                            final log = _attendanceLogs[index];
                            final isTimeIn = log.status == 'Timed In';
                            return Card(
                              color: Colors.white,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  isTimeIn ? Icons.login : Icons.logout,
                                  color: isTimeIn
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                title: Text(
                                  log.status,
                                  style: const TextStyle(color: Colors.black87),
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'MMMM dd, yyyy - hh:mm:ss a',
                                  ).format(log.time),
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // FAB OVERLAY
          if (_isFabExpanded)
            GestureDetector(
              onTap: _toggleFab,
              child: Container(
                color: Colors.black26,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
        ],
      ),

      // CUSTOM FAB MENU with orange theme
      floatingActionButton: _isFabExpanded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // DTR Button
                _buildFabMenuItem(
                  onPressed: _showDTR,
                  icon: Icons.access_time,
                  label: 'DTR',
                  color: colorScheme.secondary,
                  textColor: Colors.black87,
                ),
                const SizedBox(height: 12),

                // Profile Button
                _buildFabMenuItem(
                  onPressed: _showProfile,
                  icon: Icons.person,
                  label: 'Profile',
                  color: colorScheme.secondary.withOpacity(0.8),
                  textColor: Colors.black87,
                ),
                const SizedBox(height: 12),

                // Logout Button
                _buildFabMenuItem(
                  onPressed: _logout,
                  icon: Icons.logout,
                  label: 'Logout',
                  color: Colors.red[600]!,
                  textColor: Colors.white,
                ),
                const SizedBox(height: 16),

                // Main FAB
                FloatingActionButton.large(
                  onPressed: _toggleFab,
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5e49e4),
                  child: const Icon(Icons.close, color: Colors.black,size:32),
                ),
              ],
            )
          : FloatingActionButton.large(
              onPressed: _toggleFab,
              shape: const CircleBorder(),
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: Colors.white,
              child: const Icon(Icons.menu, color: Colors.black,size:32),
            ),
    );
  }

  // Update status display for better contrast
  Widget _buildStatusDisplay(String title, String subtitle, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Custom FAB menu item widget
  Widget _buildFabMenuItem({
    
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return ScaleTransition(
      scale: _fabScaleAnimation,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: textColor),
        label: Text(label, style: TextStyle(color: textColor)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }
}
