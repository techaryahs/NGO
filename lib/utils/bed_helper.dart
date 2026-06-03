class BedHelper {
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

  static String getBedDisplayName(String bedId) {
    final raw = bedId.trim().toLowerCase();

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