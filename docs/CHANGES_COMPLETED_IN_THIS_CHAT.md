# NGO Application Changes Completed in This Chat

**Document date:** 7 September 2026  
**Scope:** Patient stays, shifting, billing, payments, attendance, room and lobby placement, discharge checks, contact details, photographs, and related UI.

## 1. Stay history and room shifting

- The Stays tab presents a stay as an admission timeline made of room or lobby segments.
- Current admission information is presented before older discharged admission history.
- Previous room segments remain visible after a patient shifts; a room shift does not create a second unrelated admission.
- Shifting details are displayed inside the applicable current or discharged stay card.
- Every segment shows its placement period, room or lobby, bed where recorded, charged amount, and billed days.
- The start of the next segment is treated as the shift time. Timeline validation prevents a previous room from ending after the next room has begun.
- The shifting timeline editor supports editing segment dates, times, placement, bed, and charged amount.
- Room, lobby, and bed inputs use available-placement selection instead of unrestricted text where placement data is available.
- Duplicate bed choices such as two copies of `Bed 3/4` were removed from selection data.
- A stay card can be deleted. Deletion always displays an **Are you sure?** confirmation first.
- Editing or deleting a stay recalculates the admission balance and reconciles room and bed occupancy.

## 2. Billing calculation

- One admission has one combined financial balance even when the patient changes rooms.
- Payments are admission-level credits. Paying for the first room does not prevent later room charges from being added.
- A room-shift date is billed only once. When two segments touch the same date, the applicable higher room rate is used for that transfer date.
- Charges are assigned to the segment covering each billed date, so the stay card can show the charge for each room separately.
- A saved charged-amount override can replace the calculated charge for an individual stay segment.
- The single-stay editor now displays the current segment total in a visible **Charged amount** field for both active and discharged stays.
- Editing stay dates, room type, bed, pricing, attendance, or a charged-amount override triggers billing recalculation.
- Checkout is treated as 9:00 AM:
  - Exit at or before 9:00 AM does not add another billed day.
  - Exit after 9:00 AM adds that calendar day to billing.
- An active patient with a recorded exit date is billed only through that exit boundary.
- If no exit date is recorded, the application uses the seven-day estimate until an exit date is entered.
- A patient marked manually **Absent** for a date is not charged for that date.
- Paid money is never removed when the bill is recalculated. The system recalculates total, keeps receipts as credits, and derives pending or refundable amounts.

### Billing example

For a general/lobby rate of ₹200 per person per day, registration on 1 August and exit on 8 August at 9:00 AM produces seven billed days:

- Patient: 7 × ₹200 = ₹1,400
- One attendant Present for all seven days: 7 × ₹200 = ₹1,400
- Total: ₹2,800

If ₹1,500 was already paid and the attendant is later marked Present for only three days:

- Patient charge: ₹1,400
- Attendant charge: 3 × ₹200 = ₹600
- Revised total: ₹2,000
- Paid credit retained: ₹1,500
- Pending: ₹500

## 3. Patient and attendant attendance

- Patient attendance is automatically created as **Present** for the registration-to-exit date period when both boundaries are available.
- Editing the registration or exit dates synchronizes the automatic patient-attendance range.
- A manual patient **Absent** entry overrides automatic presence and reduces the charge for that day.
- Restoring an absent patient to Present restores the calculated charge.
- Attendant attendance remains manual.
- An attendant contributes to billing only for dates explicitly marked **Present**.
- An unmarked or Absent attendant does not contribute an attendant charge.
- The Add Patient total remains a seven-day estimate; it is no longer stored as a fixed patient-plus-attendant daily rate.
- Existing automatically generated daily rates are migrated to attendance-based calculation during the next billing recalculation. Rates deliberately changed in Edit Stay are explicitly marked as manual, and charged-amount overrides are preserved.
- Saving or removing an attendant-attendance mark now immediately recalculates patient billing.
- Attendant attendance is matched by date to the room segment covering that date. An attendant Present during Room 2A is charged to Room 2A; an attendant Present after a shift to Room 2B is charged to Room 2B.
- Existing dated attendance records remain usable even if the patient’s current attendant list later changes.
- The incorrect large count of unmarked days was corrected to use the patient’s actual registration-to-exit range.
- Weekly and monthly reports now request only their displayed date range instead of downloading the complete attendance history.
- Previously loaded report ranges are cached until an attendance mark changes, making repeated tab and month navigation faster.
- Weekly and monthly tables use compact headers, rows, name columns, and status cells so more records remain visible.

## 4. Payment consistency

- Overview, stay cards, Patient Billing, Patient Management, and Payment History now use consistent paid and pending calculations.
- Payment transactions remain the source of truth when older cached `totalPaidAmount` or `currentDueAmount` fields are stale.
- Same-day advance payments are accepted for the admission even when their time is earlier than the recorded registration time.
- Example: payment at 10:48 AM and registration at 3:34 PM on 1 September belong to the same admission.
- A same-day advance does not move the registration date and does not create room or attendance charges before registration.
- New payments receive an admission-cycle identifier.
- Older payments without that identifier are matched by calendar date for compatibility.
- The payment edit dialog includes **Apply payment to admission**, allowing a receipt to be moved between current and previous admission cycles without deleting it.
- Each Payment History transaction displays the room or lobby and bed for its allocated admission. Shifted admissions display the placement sequence.
- Patient Billing includes discharged patients, including discharged patients whose due amount is zero, so completed billing can still be reviewed.
- Patient Management derives the Pending Payment badge from the effective balance rather than a stale flag.
- Overpayments produce a refund-due balance. Recorded refunds reduce that balance without deleting the original receipt.

## 5. Discharge controls

- The discharge action displays the calculated total, paid amount, pending amount, and readiness information.
- Discharge is blocked when payment is incomplete.
- Discharge is also blocked when payment exceeds the bill until the refund difference is resolved.
- Patient and attendant attendance requirements are checked before discharge.
- Room and bed placement are released only after successful discharge.
- The discharge action was guarded against repeated clicks while preparation is already running.

## 6. Patient and attendant information

- Registration number is placed before patient name in the add/edit form layout.
- Editing a patient no longer downloads every patient merely to revalidate an unchanged registration number; changed/new numbers use a targeted Firebase lookup.
- Attendant mobile numbers accept digits only and require exactly ten digits in both add and edit flows.
- Emergency contact information belongs to the patient record and is displayed consistently in overview and stay details.
- If no attendant is explicitly selected as emergency contact, the first attendant is used as the name fallback.
- If that attendant has no phone number, the UI shows a dash or `N/A` rather than displaying unrelated patient data.

## 7. Photograph handling

- Patient and attendant photographs can be removed from both add and edit forms.
- Patient and attendant thumbnails can be opened in a larger preview.
- The preview was restyled as a cleaner image viewer with zoom support and less frame-like empty space.

## 8. Rooms, lobbies, and pricing

- Room occupancy is derived from actual occupied beds and active stays.
- Edit Room keeps room status, maximum attendants, and notes meaningful:
  - Occupied and pending-discharge states are derived automatically from stays.
  - Room-specific maximum attendants can override the default set in Pricing Settings.
  - Pricing Settings supplies the default maximum for rooms without a custom override.
- The room-status dropdown was corrected so duplicate values cannot trigger the Flutter `DropdownButton` assertion.
- Lobby placement is independent from physical room beds but creates a proper stay-history segment.
- Lobby placements use **General Room Pricing**, since a lobby is billed as shared/general placement.
- The add-patient payment summary no longer displays the ₹150 fallback while saved pricing is still loading.
- The form displays **Loading current pricing…** until the configured rate arrives and disables Save during that period.
- If General Room Pricing is ₹200, one lobby patient is estimated at ₹200 per day, or ₹1,400 for seven days.

## 9. Terminology and interface refinements

- Stay-history copy distinguishes a current stay from discharged stay history.
- Room/lobby/bed labels are normalized and missing bed information is shown clearly.
- The discharged-stay editor resolves a legacy saved bed ID through room inventory and writes the selected `bedLabel` when the stay is saved; headers display only the stored label.
- Charged amount is displayed and editable within the timeline segment instead of as disconnected explanatory text.
- Stay timeline and room/lobby lists received spacing, scrolling, selection-state, and card-layout improvements.
- Error handling was reduced so a temporary billing refresh timeout does not dominate the stay screen with a large raw exception message.

## 10. Current business rules

1. Patient charges begin on the registration/admission boundary, never on an earlier payment date.
2. Patient attendance is automatic for a known registration-to-exit range.
3. Attendant attendance is manual and only Present dates are charged.
4. A room-transfer date is charged once.
5. All payments remain credits when dates, rooms, attendance, or prices change.
6. Pending amount is `calculated charges − net paid`, with a minimum of zero.
7. When net paid exceeds charges, the difference becomes refund due.
8. A patient can be discharged only when attendance, payment, and refund checks are clear.

## 11. Discussed but not implemented as a separate feature

- There is no separate Lobby Pricing field. Lobby billing deliberately uses General Room Pricing.
- The application does not provisionally charge an unmarked attendant for seven days. It charges only explicitly Present attendant dates.
- Separate attendant joining and leaving date fields have not been added. Dated manual attendance is currently the source of truth for temporary attendants.
- The room/lobby label `STAY OVERDUE` remains distinct from `Occupied`: occupied describes placement usage, while overdue describes a stay past its expected end date.

## 12. Main files affected

- `lib/utils/stay_billing.dart`
- `lib/utils/pricing_helper.dart`
- `lib/services/payment_service.dart`
- `lib/services/patient_service.dart`
- `lib/services/stay_history_service.dart`
- `lib/services/room_service_stays.dart`
- `lib/models/patient_model.dart`
- `lib/screens/attendance/attendance.dart`
- `lib/screens/patients/patient_profile_screen.dart`
- `lib/screens/patients/patients_screen.dart`
- `lib/screens/patients/widgets/add_patient_dialog.dart`
- `lib/screens/patients/widgets/edit_patient_dialog.dart`
- `lib/screens/patients/widgets/inline_stay_editor.dart`
- `lib/screens/patients/widgets/shift_timeline_editor.dart`
- `lib/screens/patients/widgets/stay_history_card.dart`
- `lib/screens/patients/widgets/stay_history_tab.dart`
- `lib/screens/patients/widgets/photo_preview_dialog.dart`
- `lib/screens/patients/widgets/patient_card.dart`
- `lib/screens/payments/payments_screen.dart`
- `lib/screens/rooms/rooms_page.dart`
- `lib/screens/rooms/widgets/edit_room_dialog.dart`
- `lib/screens/rooms/widgets/pricing_settings_dialog.dart`
- `test/stay_billing_test.dart`

## 13. Validation note

Focused billing tests were expanded to cover exit-date billing, transfer-day billing, attendance adjustments, refunds, attendant attendance, and legacy same-day payments. During the latest validation attempts, Flutter/Dart commands stalled without output in the local environment and were stopped, so a complete final automated test run is still required before release.

## 14. Komal lobby billing correction

- A legacy patient-level amount such as ₹3,600 no longer overrides an existing stay's attendance-aware bill. Patient-level overrides remain supported only for records that have no stay segments; manual final charge changes belong to the relevant stay.
- For Komal's 1–10 August period with a 9:00 AM checkout, the patient has nine billable days. At ₹200 per day the patient charge is ₹1,800. Six attendant Present dates add ₹1,200, producing a ₹3,000 total, ₹800 paid, and ₹2,200 pending.
- Edit Patient again displays a compact Current Billing summary with Total, Paid, and Pending. It no longer displays a provisional ₹150/₹300 daily estimate that assumes every attendant is present for every patient day.
- General room and lobby test expectations were updated from the retired ₹150 fallback to ₹200, and a regression case now confirms that a legacy ₹3,600 override cannot replace Komal's ₹3,000 attendance-aware stay bill.

## 15. Ongoing stays after shifting

- The shift confirmation now includes **No exit date — stay is ongoing**. It is selected automatically when the patient has no exit date, and the saved shift keeps `exitDate` empty.
- Edit Patient contains the same option, allowing an existing exit date to be cleared. With no exit date, billing uses the seven-day default until a date is entered.
- Add Patient now also supports **Planned exit date not decided**. It uses the seven-day estimate initially without saving that estimate as an actual exit date.
- The current segment in Edit Shifting Timeline can display **Planned exit date: Not decided** while keeping the stay open.
- Active patient Overview and Stay cards label the value **Planned Exit Date**. Completed patients and stays label the recorded value **Actual Discharge Date**.

## 16. Shifting timeline save timeout

- Timeline saving no longer downloads the complete stay history before recalculating billing. It queries the indexed `patientId` field and loads only the selected patient's stays, preventing the `Failed to GET stays: Request timeout` error on larger databases.

## 17. Patient attendance overall summary

- The Overall Summary now identifies the patient by name with a **PATIENT** label and identifies every accompanying person with an **ATTENDANT** label.
- Summary cards now use a compact modern layout with role icons, Present, Absent, Marked totals, attendance percentage, consistent spacing, rounded cards, and a people count in the heading.
- The cards were further condensed into single-row summaries with small `P`, `A`, and `Total` pills so the complete list requires much less vertical scrolling.
- All attendant rows now share one white **Attendants** card with subtle dividers, while the patient keeps a separate card.

## 18. Ongoing stay badge

- Room and lobby cards now show **ONGOING** when the planned exit date is not decided. The `days left` and `STAY OVERDUE` states are shown only when the patient has an actual planned exit date.

## 19. Complete patient deletion and orphan repair

- Patient deletion is now one coordinated cleanup: patient record, all stay records, patient and attendant attendance, payment history, transaction ledger entries, room/lobby occupancy, bed ownership, and room census are removed together.
- Cleanup queries stays and payments by indexed `patientId` instead of downloading their complete collections.
- Patient, Attendance, Payments, and Rooms screens run a guarded orphan repair for records left by the older partial-delete behavior. This releases beds such as Komal's 10/11 and removes her remaining dashboard and ledger rows.
- Orphan checks are no longer permanently cached after an earlier empty result. Room Details directly detects a stay whose patient no longer exists, runs an immediate repair, closes the stale dialog, refreshes the room, and confirms that the bed was released.
- Room Details now subscribes to the live room record instead of retaining the room snapshot from the moment the dialog opened. It also immediately hides an occupied bed whose `currentPatientId` no longer exists while the backend repair finishes, keeping the status, occupied count, bed badges, and active-stay list consistent.
# Room card cleanup after patient deletion

- Room cards now verify occupied bed assignments against the live active-patient list.
- A deleted patient's bed is immediately displayed as available, and the card recalculates its occupied count and room status.
- Stale vacancy dates linked to removed assignments are no longer displayed.
