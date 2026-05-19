import 'package:flutter/material.dart';

import 'package:ngo/models/bed_model.dart';

class CreateStayBedSelectionGrid extends StatelessWidget {
  final List<BedModel> beds;
  final BedModel? selectedBed;
  final Function(BedModel) onBedSelected;
  final String roomType;

  const CreateStayBedSelectionGrid({
    super.key,
    required this.beds,
    required this.selectedBed,
    required this.onBedSelected,
    required this.roomType,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, BedModel> uniqueBeds = {};
    for (final bed in beds) {
      final label = BedModel.formatBedLabel(bed.bedLabel, roomType);
      final existing = uniqueBeds[label];
      if (existing == null || (!existing.isAvailable && bed.isAvailable)) {
        uniqueBeds[label] = bed;
      }
    }
    final displayBeds = uniqueBeds.values.toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: displayBeds.map((bed) {
        final isSelected = selectedBed != null && 
            BedModel.formatBedLabel(selectedBed!.bedLabel, roomType) == BedModel.formatBedLabel(bed.bedLabel, roomType);
        final isAvailable = bed.isAvailable;

        Color bgColor;
        Color textColor;
        Color borderColor;

        if (isSelected) {
          bgColor = const Color(0xFF3B6D11);
          textColor = Colors.white;
          borderColor = const Color(0xFF3B6D11);
        } else if (!isAvailable) {
          bgColor = const Color(0xFFFFE5E7);
          textColor = const Color(0xFFD32F2F).withOpacity(0.5);
          borderColor = const Color(0xFFE8B4B8);
        } else {
          bgColor = const Color(0xFFF4F9F0);
          textColor = const Color(0xFF27500A);
          borderColor = const Color(0xFFC0DD97);
        }

        return InkWell(
          onTap: isAvailable ? () => onBedSelected(bed) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAvailable ? Icons.bed_outlined : Icons.bed_rounded,
                  size: 16,
                  color: textColor,
                ),
                const SizedBox(width: 6),
                Text(
                  BedModel.formatBedLabel(bed.bedLabel, roomType),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class CreateStayCountChip extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const CreateStayCountChip({
    super.key,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B6D11)
                : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF27500A),
          ),
        ),
      ),
    );
  }
}
