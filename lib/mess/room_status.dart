import 'package:flutter/material.dart';
import 'empty_rooms.dart';
import 'occupied_rooms.dart';

class RoomStatusScreen extends StatefulWidget {
  const RoomStatusScreen({super.key});

  @override
  State<RoomStatusScreen> createState() => _RoomStatusScreenState();
}

class _RoomStatusScreenState extends State<RoomStatusScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(
                'Room Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
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
        body: const TabBarView(
          children: [
            EmptyRoomsTab(),
            OccupiedRoomsTab(),
          ],
        ),
      ),
    );
  }
}