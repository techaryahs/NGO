import 'package:flutter/material.dart';

import '../../../models/bed_model.dart';
import '../../../models/room_model.dart';

class PatientFormSection extends StatelessWidget {
  final String label;
  final Widget child;

  const PatientFormSection({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF639922),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(color: Color(0xFFC0DD97), thickness: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class PatientFormRow2 extends StatelessWidget {
  final Widget a;
  final Widget b;

  const PatientFormRow2(this.a, this.b, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }
}

class PatientFormRow3 extends StatelessWidget {
  final Widget a;
  final Widget b;
  final Widget c;

  const PatientFormRow3(this.a, this.b, this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
        const SizedBox(width: 12),
        Expanded(child: c),
      ],
    );
  }
}

class PatientFormField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isDate;
  final TextInputType keyboard;
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final int maxLines;

  const PatientFormField({
    super.key,
    required this.label,
    required this.hint,
    this.isDate = false,
    this.keyboard = TextInputType.text,
    this.controller,
    this.onTap,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          readOnly: isDate,
          onTap: onTap,
          keyboardType: isDate ? TextInputType.datetime : keyboard,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          decoration: InputDecoration(
            hintText: isDate ? 'DD / MM / YYYY' : hint,
            hintStyle: TextStyle(
              color: const Color(0xFF97C459).withValues(alpha: 0.75),
              fontSize: 13,
            ),
            suffixIcon: isDate
                ? const Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF639922),
                    size: 16,
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF639922),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PatientFormDropdown extends StatelessWidget {
  final String label;
  final List<String> items;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final String hint;

  const PatientFormDropdown({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hint = 'Select',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          hint: Text(
            hint,
            style: TextStyle(
              color: const Color(0xFF97C459).withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          dropdownColor: const Color(0xFFF4F9F0),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF639922),
                width: 1.5,
              ),
            ),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF639922),
            size: 20,
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class PatientRoomDropdown extends StatelessWidget {
  final String label;
  final List<RoomModel> rooms;
  final RoomModel? selectedRoom;
  final ValueChanged<RoomModel?>? onChanged;
  final bool Function(RoomModel room)? isRoomEnabled;
  final Widget Function(RoomModel room, bool enabled)? itemBuilder;

  const PatientRoomDropdown({
    super.key,
    required this.label,
    required this.rooms,
    this.selectedRoom,
    this.onChanged,
    this.isRoomEnabled,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<RoomModel>(
          initialValue: selectedRoom,
          hint: Text(
            'Select room',
            style: TextStyle(
              color: const Color(0xFF97C459).withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          dropdownColor: const Color(0xFFF4F9F0),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF639922),
                width: 1.5,
              ),
            ),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF639922),
            size: 20,
          ),
          items: rooms.map((room) {
            final enabled = isRoomEnabled?.call(room) ?? true;
            final defaultItem = Text(
              '${room.roomIdentifier} - ${room.actualAvailableBeds} beds available',
              style: TextStyle(
                fontSize: 13,
                color: enabled
                    ? const Color(0xFF27500A)
                    : const Color(0xFF999999),
              ),
            );

            return DropdownMenuItem(
              value: room,
              enabled: enabled,
              child: itemBuilder?.call(room, enabled) ?? defaultItem,
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class PatientBedSelection extends StatelessWidget {
  final String label;
  final List<BedModel> beds;
  final List<BedModel> selectedBeds;
  final bool isPrivateRoom;
  final ValueChanged<List<BedModel>>? onChanged;

  const PatientBedSelection({
    super.key,
    required this.label,
    required this.beds,
    required this.selectedBeds,
    this.isPrivateRoom = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.5,
              ),
            ),
            if (selectedBeds.isNotEmpty)
              Text(
                '${selectedBeds.length} selected',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF3B6D11),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (beds.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE69C)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF856404), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No beds available in this room',
                    style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: beds.map((bed) {
                  final isSelected = selectedBeds.any((b) => b.id == bed.id);
                  return FilterChip(
                    label: Text('Bed ${bed.bedLabel}'),
                    selected: isSelected,
                    onSelected: isPrivateRoom ? null : (selected) {
                      final newSelection = List<BedModel>.from(selectedBeds);
                      if (selected) {
                        newSelection.add(bed);
                      } else {
                        newSelection.removeWhere((b) => b.id == bed.id);
                      }
                      onChanged?.call(newSelection);
                    },
                    backgroundColor: const Color(0xFFF4F9F0),
                    selectedColor: const Color(0xFF3B6D11),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF27500A),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF3B6D11)
                          : const Color(0xFFC0DD97),
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Color(0xFF3B6D11),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPrivateRoom
                            ? 'Private room books the entire room (all beds automatically selected)'
                            : 'You can select multiple beds for patient + attendants',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3B6D11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}


// -- Shared Header & Footer ------------------------------------------------------------

class PatientDialogHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  const PatientDialogHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(
          bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC0DD97), width: 1.5),
            ),
            child: Icon(icon, color: const Color(0xFF3B6D11), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF27500A)),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF639922))),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class PatientDialogFooter extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool isLoading;
  final String submitLabel;

  const PatientDialogFooter({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.isLoading = false,
    this.submitLabel = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(top: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: isLoading ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF639922),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFC0DD97)),
              ),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEAF3DE))))
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(isLoading ? 'Processing...' : submitLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: const Color(0xFFEAF3DE),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
