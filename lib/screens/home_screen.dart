import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../services/location_service.dart';

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

class _MyHomePageState extends State<MyHomePage> {
  // Gamitin natin ang bagong LocationService
  final LocationService _locationService = LocationService();

  // State variables para sa attendance
  bool _isTimedIn = false;
  DateTime? _timeInTimestamp;
  final List<AttendanceLog> _attendanceLogs = [];


  @override
  void initState() {
    super.initState();
    
  }

  @override
  void dispose() {
    _locationService.stop(); 
    super.dispose();
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
        _attendanceLogs.insert(0, AttendanceLog(time: now, status: 'Timed Out'));
        
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Time In/Out Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_isTimedIn && _timeInTimestamp != null)
                      _buildStatusDisplay(
                        'You are currently timed in since:',
                        DateFormat('hh:mm a').format(_timeInTimestamp!),
                        colorScheme.primary,
                      )
                    else
                      _buildStatusDisplay(
                        'You are currently timed out.',
                        'Press button to time in.',
                        colorScheme.secondary,
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      // ============== ITO ANG PAGBABAGO SA BUTTON ==============
                      child: _isTimedIn
                          ? FilledButton.tonalIcon(
                              onPressed: _toggleTimeIn, // Palitan ito
                              icon: const Icon(Icons.logout),
                              label: const Text('Time Out'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _toggleTimeIn, // At palitan din ito
                              icon: const Icon(Icons.login),
                              label: const Text('Time In'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            Text('Attendance Logs', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),

            // Attendance Logs List
            Expanded(
              child: _attendanceLogs.isEmpty
                  ? const Center(
                      child: Text('No attendance logs yet.'),
                    )
                  : ListView.builder(
                      itemCount: _attendanceLogs.length,
                      itemBuilder: (context, index) {
                        final log = _attendanceLogs[index];
                        final isTimeIn = log.status == 'Timed In';
                        return ListTile(
                          leading: Icon(
                            isTimeIn ? Icons.login : Icons.logout,
                            color: isTimeIn ? Colors.green : Colors.orange,
                          ),
                          title: Text(log.status),
                          subtitle: Text(
                            DateFormat('MMMM dd, yyyy - hh:mm:ss a').format(log.time),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDisplay(String title, String subtitle, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
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
}