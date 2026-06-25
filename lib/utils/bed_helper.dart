class BedHelper {
  static const _lobbyRooms = {'1B', '1D', '2B', '2E'};

  static bool isLobbyRoom(String? roomIdentifier) {
    return _lobbyRooms.contains(roomIdentifier?.trim().toUpperCase());
  }

  static const _roomBedLabels = {
    '1A': {'bed1': 'Bed 1/2', '1': 'Bed 1/2', '2': 'Bed 1/2'},
    '1B': {
      'bed1': 'Bed 3/4',
      'bed2': 'Bed 3/4',
      'bed3': 'Bed 5/6',
      'bed4': 'Bed 5/6',
      'bed5': 'Bed 7',
      '1': 'Bed 3/4',
      '2': 'Bed 3/4',
      '3': 'Bed 5/6',
      '4': 'Bed 5/6',
      '5': 'Bed 7',
    },
    '1C': {
      'bed1': 'Bed 8/9',
      'bed2': 'Bed 8/9',
      'bed3': 'Bed 10/11',
      'bed4': 'Bed 10/11',
      '1': 'Bed 8/9',
      '2': 'Bed 8/9',
      '3': 'Bed 10/11',
      '4': 'Bed 10/11',
    },
    '1D': {
      'bed1': 'Bed 12/13',
      'bed2': 'Bed 12/13',
      'bed3': 'Bed 14/15',
      'bed4': 'Bed 14/15',
      'bed5': 'Bed 16/17',
      'bed6': 'Bed 16/17',
      'bed7': 'Bed 18/19',
      'bed8': 'Bed 18/19',
      'bed9': 'Bed 20/21',
      'bed10': 'Bed 20/21',
      'bed11': 'Bed 22/23',
      'bed12': 'Bed 22/23',
      '1': 'Bed 12/13',
      '2': 'Bed 12/13',
      '3': 'Bed 14/15',
      '4': 'Bed 14/15',
      '5': 'Bed 16/17',
      '6': 'Bed 16/17',
      '7': 'Bed 18/19',
      '8': 'Bed 18/19',
      '9': 'Bed 20/21',
      '10': 'Bed 20/21',
      '11': 'Bed 22/23',
      '12': 'Bed 22/23',
    },
    '2A': {'bed1': 'Bed 1/2', '1': 'Bed 1/2', '2': 'Bed 1/2'},
    '2B': {'bed1': 'Bed 3/4', '1': 'Bed 3/4', '2': 'Bed 3/4'},
    '2C': {
      'bed1': 'Bed 5/6',
      'bed2': 'Bed 5/6',
      'bed3': 'Bed 7/8',
      'bed4': 'Bed 7/8',
      'bed5': 'Bed 9',
      '1': 'Bed 5/6',
      '2': 'Bed 5/6',
      '3': 'Bed 7/8',
      '4': 'Bed 7/8',
      '5': 'Bed 9',
    },
    '2D': {
      'bed1': 'Bed 10/11',
      'bed2': 'Bed 10/11',
      'bed3': 'Bed 12/13',
      'bed4': 'Bed 12/13',
      '1': 'Bed 10/11',
      '2': 'Bed 10/11',
      '3': 'Bed 12/13',
      '4': 'Bed 12/13',
    },
    '2E': {
      'bed1': 'Bed 14/15',
      'bed2': 'Bed 14/15',
      'bed3': 'Bed 16/17',
      'bed4': 'Bed 16/17',
      'bed5': 'Bed 18/19',
      'bed6': 'Bed 18/19',
      'bed7': 'Bed 20/21',
      'bed8': 'Bed 20/21',
      'bed9': 'Bed 22/23',
      'bed10': 'Bed 22/23',
      'bed11': 'Bed 24/25',
      'bed12': 'Bed 24/25',
      '1': 'Bed 14/15',
      '2': 'Bed 14/15',
      '3': 'Bed 16/17',
      '4': 'Bed 16/17',
      '5': 'Bed 18/19',
      '6': 'Bed 18/19',
      '7': 'Bed 20/21',
      '8': 'Bed 20/21',
      '9': 'Bed 22/23',
      '10': 'Bed 22/23',
      '11': 'Bed 24/25',
      '12': 'Bed 24/25',
    },
  };

  static const _publicBedLabels = {
    'bed1': 'Bed 1/2',
    'bed2': 'Bed 3/4',
    'bed3': 'Bed 5/6',
    'bed4': 'Bed 7/8',
    'bed5': 'Bed 9/10',
    'bed6': 'Bed 11/12',
    'bed7': 'Bed 13/14',
    'bed8': 'Bed 15/16',
    'bed9': 'Bed 17/18',
    'bed10': 'Bed 19/20',
    'bed11': 'Bed 21/22',
    'bed12': 'Bed 23/24',
  };

  static String getBedDisplayName(String bedId, {String? roomIdentifier}) {
    final raw = bedId.trim().toLowerCase();

    if (raw.startsWith('lobby')) {
      final number = RegExp(r'\d+').firstMatch(raw)?.group(0);
      return number == null ? 'Lobby' : 'Lobby $number';
    }

    final roomLabels = _roomBedLabels[roomIdentifier?.trim().toUpperCase()];

    if (roomLabels != null && roomLabels.containsKey(raw)) {
      return roomLabels[raw]!;
    }

    if (roomLabels != null) {
      final directLabel = roomLabels.entries
          .where(
            (entry) =>
                entry.value.toLowerCase() == raw ||
                entry.value.toLowerCase() == 'bed $raw',
          )
          .map((entry) => entry.value)
          .firstOrNull;
      if (directLabel != null) return directLabel;
    }

    // New format: bed1, bed2, bed3...
    if (_publicBedLabels.containsKey(raw)) {
      return _publicBedLabels[raw]!;
    }

    // Legacy numeric values
    final number = int.tryParse(raw);

    if (number != null && number > 0) {
      final start = ((number - 1) * 2) + 1;
      final end = start + 1;

      return 'Bed $start/$end';
    }

    // Private room labels such as 1A, 1B, etc.
    return raw;
  }
}
