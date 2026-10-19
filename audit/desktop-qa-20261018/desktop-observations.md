# Actual Windows desktop observations — 18 October 2026

This is an in-progress record, not a declaration that all workflows passed.

## Environment and preservation

- Existing Git changes preserved; initial status saved under `.gravitas/sessions/desktop-qa-20261018/`.
- Existing `ngo-postgres` PostgreSQL 16 and `ngo-backend` Docker containers were healthy.
- Local `/health` and `/ready`: HTTP 200; readiness reported database latency 2 ms. PowerShell request wall times were 415 ms (cold health client) and 10 ms (ready).
- Root and release-asset configuration: `USE_POSTGRES_BACKEND=true`, `BACKEND_API_URL=http://localhost:8080/api`. Secret values were not printed.
- Workspace release built successfully, then launched from `C:\Users\sahil\OneDrive\Desktop\NGO\build\windows\x64\runner\Release\ngo.exe`.
- Existing Firebase Authentication session restored. No password entered, authentication disabled, role changed, production deployment or data reset.
- The launcher initially selected the installed copy despite the workspace path. That copy was closed without data mutations. Exact workspace process path was then confirmed through process inspection and Computer Use window identity.

## Startup routing defect, reproduced and retested

The workspace app initially opened the Volunteer Portal despite authoritative PostgreSQL admin access and HTTP 200 from `/api/users/<current UID>` (11.4 ms). Cache account activation raced the initial role lookup; its failure was swallowed and the null result cached as volunteer routing.

After the auth/cache fix, a rebuilt release restored the same Firebase session and opened the admin Patient Portal, exposing Patients, Rooms, Attendance, Payments and Inventory. No database role changes were made.

## Add Patient loading, reproduced

- Actual clicks: Patients, then Add Patient.
- Patients click to first screenshot: 313 ms. Add Patient click to first modal screenshot: 274 ms (this only measures initial presentation, not usable room selection).
- Actual release stdout:

```text
[ADD PATIENT] rooms load failed: TimeoutException after 0:00:08.000000: Future not completed
[ADD PATIENT] active stays load failed: TimeoutException after 0:00:08.000000: Future not completed
```

Backend rooms/stays polls returned HTTP 200 in approximately 3–15 ms around the failure. Late dialog listeners received an existing broadcast stream without replay, whose next poll was 10 seconds later, beyond the 8-second dialog timeout. Closing and reopening the dialog at another poll phase allowed room selection.

## Registration HTTP 400, reproduced

Through the actual UI: synthetic name `qa18`, DOB 1 January 1990, synthetic mobile `9000018018`, Male, diagnosis `qa`, attendant `qa`, floor 1, room 1A, automatically selected bed 1/2. No actual Aadhaar/PAN/photo information was used.

The enrollment screen displayed a seven-day estimate at ₹200/day, total ₹1,400. Save clicked at Unix epoch milliseconds 1792327837619. First screenshot 413 ms later showed the red HTTP 400 snackbar. The dialog remained open and no success message appeared.

Actual release stdout (schema diagnostic excludes submitted payload and tokens):

```text
[ADD PATIENT] STEP room-validation SUCCESS elapsed=28ms
[RegistrationNumberService] postgres allocated=4
[ADD PATIENT] STEP registration-allocation SUCCESS regNo=4 elapsed=10ms
[BackendApiService] registerPatient rejected: Invalid request: fullName: Required; dateOfBirth: Invalid input; gender: Required; contactNumber: Required; emergencyContact: Required; emergencyContactName: Required; medicalCondition: Required; admissionDate: Invalid input; initialAttendance: Expected array, received object
[ADD PATIENT] STEP FAILED elapsed=53ms: Exception: Failed to add patient: HttpException: registerPatient failed (HTTP 400)
```

Flutter submitted nested `patient` plus path-keyed attendance; the backend requires flat patient fields and `{date,kind,payload}` attendance array. Backend input validation remains intact.

## Computer Use limitation/workaround

Mouse controls and individual keyboard presses work. Bulk `type_text` did not change Flutter fields; `set_value` reported that the observed element was unavailable in cached app state, including after a documented connection reset. Synthetic text was entered with supported single-key events, with field/screenshot verification. Form-filling automation overhead is excluded from application latency claims.

## Pending desktop workflows

Corrected registration/bed allocation, synthetic room creation/two beds, attendance/attendant attendance persistence and billing corrections, cash/UPI recording, discharge and restart persistence have not yet been verified.
