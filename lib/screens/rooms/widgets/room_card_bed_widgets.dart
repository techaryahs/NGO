import 'package:flutter/material.dart';
import 'package:ngo/models/bed_model.dart';

class RoomBedGrid extends StatelessWidget {
  final List<BedModel> beds;

  const RoomBedGrid({super.key, required this.beds});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: beds.map((bed) => RoomBedChip(bed: bed)).toList(),
    );
  }
}

class RoomBedChip extends StatelessWidget {
  final BedModel bed;

  const RoomBedChip({super.key, required this.bed});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    switch (bed.status) {
      case 'occupied':
        bgColor = const Color(0xFFFFE5E7);
        textColor = const Color(0xFFD32F2F);
        borderColor = const Color(0xFFE8B4B8);
        icon = Icons.bed_rounded;
        break;
      case 'maintenance':
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        borderColor = const Color(0xFFFFB74D);
        icon = Icons.build_rounded;
        break;
      default:
        bgColor = const Color(0xFFE8F5E0);
        textColor = const Color(0xFF3B6D11);
        borderColor = const Color(0xFFC0DD97);
        icon = Icons.bed_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            bed.bedLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
