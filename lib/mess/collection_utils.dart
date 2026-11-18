// lib/utils/collection_utils.dart

class CollectionUtils {
  /// Groups raw Supabase payments into a nested Month -> Room structure.
  ///
  /// Structure returned:
  /// {
  ///   "December 2026": {
  ///     "total_collection": 15000.0,
  ///     "rooms": {
  ///       "201": {
  ///         "room_number": "201",
  ///         "total_rent": 4000.0,
  ///         "total_elec": 500.0,
  ///         "room_total": 4500.0,
  ///         "members": [
  ///           {"name": "Fahim", "rent": 2000.0, "elec": 250.0, "total": 2250.0}
  ///         ]
  ///       }
  ///     }
  ///   }
  /// }
  static Map<String, Map<String, dynamic>> groupCollectionsByMonth(
  List payments) {
  final Map<String, Map<String, dynamic>> groupedData = {};

  for (final p in payments) {
  final monthYear = p['month_year'] ?? 'Unknown Month';

  // Extract member details whether from joined mess_members map or raw payload
  final memberInfo = p['mess_members'] is Map<String, dynamic>
  ? p['mess_members']
      : <String, dynamic>{};

  final roomNo = (memberInfo['occupied_rooms'] ?? p['occupied_rooms'] ?? 'N/A').toString();
  final memberName = (memberInfo['name'] ?? p['member_name'] ?? 'Unknown Member').toString();

  final rent = (p['rent_amount'] as num?)?.toDouble() ?? 0.0;
  final elec = (p['electricity_bill'] as num?)?.toDouble() ?? 0.0;
  final totalPaid = (p['total_paid'] as num?)?.toDouble() ?? (rent + elec);

  // 1. Initialize Month entry if missing
  groupedData.putIfAbsent(monthYear, () => {
  'total_collection': 0.0,
  'rooms': <String, Map<String, dynamic>>{},
  });

  // Aggregate month total
  groupedData[monthYear]!['total_collection'] =
  (groupedData[monthYear]!['total_collection'] as double) + totalPaid;

  final roomsMap = groupedData[monthYear]!['rooms'] as Map<String, dynamic>;

  // 2. Initialize Room entry if missing
  roomsMap.putIfAbsent(roomNo, () => {
  'room_number': roomNo,
  'total_rent': 0.0,
  'total_elec': 0.0,
  'room_total': 0.0,
  'members': [],
  });

  // Aggregate room totals
  roomsMap[roomNo]['total_rent'] = (roomsMap[roomNo]['total_rent'] as double) + rent;
  roomsMap[roomNo]['total_elec'] = (roomsMap[roomNo]['total_elec'] as double) + elec;
  roomsMap[roomNo]['room_total'] = (roomsMap[roomNo]['room_total'] as double) + totalPaid;

  // Append individual member payment breakdown
  (roomsMap[roomNo]['members'] as List).add({
  'name': memberName,
  'rent': rent,
  'elec': elec,
  'total': totalPaid,
  'payment_date': p['payment_date'] ?? '',
  });
  }

  return groupedData;
  }
}