# Local Development Environment Guide

This document describes how to configure environment variables and runtime settings for running the backend Cloud Functions and the Flutter client locally.

---

### Backend Environment

File: `functions/.env.local`

The backend reads configuration directly from `process.env`. Modern Firebase CLI automatically loads environment variables from `functions/.env.local` during local emulation (`firebase emulators:start`).

A template is provided in `functions/.env.example`.

#### Variables:
- **`RAZORPAY_KEY_ID`**: Your Razorpay Key ID (e.g. `rzp_test_...`). Required for creating and looking up Razorpay payment links.
- **`RAZORPAY_KEY_SECRET`**: Your Razorpay Key Secret. Required for authenticating server-to-server requests with the Razorpay REST API.
- **`RAZORPAY_WEBHOOK_SECRET`**: Secret configured in Razorpay Dashboard for webhook verification. Required for validating incoming `payment_link.paid` webhook events via HMAC-SHA256 signature.
- **`FIREBASE_CONFIG`**: JSON string containing `projectId` and `databaseURL` (`{"projectId":"ngo-management-system-d8c06","databaseURL":"https://ngo-management-system-d8c06-default-rtdb.asia-southeast1.firebasedatabase.app"}`). Required because the project's Realtime Database is hosted in the `asia-southeast1` region.
- **`GOOGLE_APPLICATION_CREDENTIALS`**: Path to a Firebase service account JSON key file (e.g. `C:\path\to\service-account.json`). Required for Firebase Admin SDK to authenticate against the production/staging Firebase project when running functions locally without an offline database emulator.

---

### Flutter Runtime

The Flutter client NEVER contains secrets. It only needs the trusted payment backend URL, passed at run/build time via `--dart-define`:

```cmd
flutter run -d windows --dart-define=RAZORPAY_BACKEND_URL=<backend-url>
```

For local Firebase Functions emulator execution, the current backend serves HTTP functions under:

```text
http://127.0.0.1:5001/ngo-management-system-d8c06/us-central1
```

Command:
```cmd
flutter run -d windows --dart-define=RAZORPAY_BACKEND_URL=http://127.0.0.1:5001/ngo-management-system-d8c06/us-central1
```

---

### Important

> [!CAUTION]
> `functions/.env.local` contains sensitive secrets (API keys, webhook secrets, and private paths). It is listed in `.gitignore` and **must never be committed to version control**. Only commit `functions/.env.example` with sanitized placeholder values.
