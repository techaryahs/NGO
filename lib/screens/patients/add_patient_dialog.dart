import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class AddPatientDialog extends StatelessWidget {
  const AddPatientDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 620,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Section(
                        label: "Patient information",
                        child: Column(
                          children: [
                            _Row2(
                              _NatureField(label: "Date", hint: "", isDate: true),
                              _NatureField(label: "File no", hint: "e.g. F-2024-001"),
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(label: "Patient name", hint: "Full name"),
                              _NatureField(label: "Mobile no", hint: "+91 XXXXX XXXXX", keyboard: TextInputType.phone),
                            ),
                            const SizedBox(height: 12),
                            _Row3(
                              _NatureDropdown(
                                label: "Gender",
                                items: const ["Male", "Female", "Other"],
                              ),
                              _NatureField(label: "Age", hint: "Years", keyboard: TextInputType.number),
                              _NatureField(label: "Pincode", hint: "000000", keyboard: TextInputType.number),
                            ),
                            const SizedBox(height: 12),
                            _NatureField(label: "Permanent address", hint: "Street, city, district"),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(label: "State", hint: "State"),
                              _NatureField(label: "Mumbai local contact address", hint: "Local address"),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Medical details",
                        child: Column(
                          children: [
                            _NatureField(label: "Diagnosis", hint: "Primary diagnosis"),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(label: "Doctor name", hint: "Dr. name"),
                              _NatureField(label: "Hospital name", hint: "Hospital / clinic"),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Attendant details",
                        child: _Row3(
                          _NatureField(label: "Attendant name", hint: "Full name"),
                          _NatureField(label: "Attendant age", hint: "Years", keyboard: TextInputType.number),
                          _NatureField(label: "Relation to patient", hint: "e.g. Spouse"),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Office use",
                        child: SizedBox(
                          width: 180,
                          child: _NatureField(label: "Bed no", hint: "e.g. B-04"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _DialogFooter(onCancel: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
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
            child: const Icon(Icons.person_add_outlined, color: Color(0xFF3B6D11), size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Add patient",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF27500A)),
              ),
              Text(
                "Fill in the details below to register a new patient",
                style: TextStyle(fontSize: 12, color: Color(0xFF639922)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _DialogFooter extends StatelessWidget {
  final VoidCallback onCancel;
  const _DialogFooter({required this.onCancel});

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
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF639922),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFC0DD97)),
              ),
            ),
            child: const Text("Cancel", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text("Save patient", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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

// ── Section ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

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
            const Expanded(child: Divider(color: Color(0xFFC0DD97), thickness: 0.5)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// ── Grid helpers ──────────────────────────────────────────────────────────────

class _Row2 extends StatelessWidget {
  final Widget a, b;
  const _Row2(this.a, this.b);

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

class _Row3 extends StatelessWidget {
  final Widget a, b, c;
  const _Row3(this.a, this.b, this.c);

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

// ── Field ─────────────────────────────────────────────────────────────────────

class _NatureField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isDate;
  final TextInputType keyboard;

  const _NatureField({
    required this.label,
    required this.hint,
    this.isDate = false,
    this.keyboard = TextInputType.text,
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
          keyboardType: isDate ? TextInputType.datetime : keyboard,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          decoration: InputDecoration(
            hintText: isDate ? "DD / MM / YYYY" : hint,
            hintStyle: TextStyle(
              color: const Color(0xFF97C459).withOpacity(0.75),
              fontSize: 13,
            ),
            suffixIcon: isDate
                ? const Icon(Icons.calendar_today_outlined, color: Color(0xFF639922), size: 16)
                : null,
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Dropdown ──────────────────────────────────────────────────────────────────

class _NatureDropdown extends StatefulWidget {
  final String label;
  final List<String> items;
  const _NatureDropdown({required this.label, required this.items});

  @override
  State<_NatureDropdown> createState() => _NatureDropdownState();
}

class _NatureDropdownState extends State<_NatureDropdown> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: selected,
          hint: Text(
            "Select",
            style: TextStyle(color: const Color(0xFF97C459).withOpacity(0.75), fontSize: 13),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          dropdownColor: const Color(0xFFF4F9F0),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922), size: 20),
          items: widget.items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => setState(() => selected = v),
        ),
      ],
    );
  }
}