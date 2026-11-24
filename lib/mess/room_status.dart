import 'package:flutter/material.dart';
import 'empty_rooms.dart';
import 'occupied_rooms.dart';

class RoomStatusScreen extends StatefulWidget {
  final String? messId;
  final String? messName;

  const RoomStatusScreen({
    super.key,
    this.messId,
    this.messName,
  });

  @override
  State<RoomStatusScreen> createState() => _RoomStatusScreenState();
}

class _RoomStatusScreenState extends State<RoomStatusScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMess = widget.messId != null && widget.messId!.trim().isNotEmpty;
    final subtitle = (widget.messName != null && widget.messName!.trim().isNotEmpty)
        ? widget.messName!.trim()
        : null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Room Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          bottom: const TabBar(
            indicatorWeight: 3,
            tabs: [
              Tab(
                icon: Icon(Icons.meeting_room_outlined),
                text: 'Empty Rooms',
              ),
              Tab(
                icon: Icon(Icons.sensor_door),
                text: 'Occupied Rooms',
              ),
            ],
          ),
        ),
        body: TabBarView(
          key: ValueKey(hasMess ? widget.messId : 'all_messes'),
          children: [
            EmptyRoomsTab(
              messId: widget.messId,
              messName: widget.messName,
            ),
            OccupiedRoomsTab(
              messId: widget.messId,
              messName: widget.messName,
            ),
          ],
        ),
      ),
    );
  }
}