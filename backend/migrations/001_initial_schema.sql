-- Up Migration

-- 1. Users & Staff Accounts
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(64) PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(32),
    role VARCHAR(32) NOT NULL DEFAULT 'volunteer',
    password_hash VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_users_email ON users(email);

-- 2. Rooms
CREATE TABLE IF NOT EXISTS rooms (
    id VARCHAR(64) PRIMARY KEY,
    room_number VARCHAR(32) NOT NULL,
    room_identifier VARCHAR(32),
    floor INTEGER NOT NULL DEFAULT 1,
    room_type VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'available',
    max_attendants INTEGER NOT NULL DEFAULT 5,
    current_attendants INTEGER NOT NULL DEFAULT 0,
    has_custom_attendant_limit BOOLEAN NOT NULL DEFAULT FALSE,
    total_beds INTEGER NOT NULL DEFAULT 0,
    occupied_beds INTEGER NOT NULL DEFAULT 0,
    expected_vacancy_date TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_rooms_room_number ON rooms(room_number);
CREATE INDEX IF NOT EXISTS ix_rooms_floor ON rooms(floor);
CREATE INDEX IF NOT EXISTS ix_rooms_status ON rooms(status);

-- 3. Room Beds
CREATE TABLE IF NOT EXISTS room_beds (
    id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    bed_label VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'available',
    current_patient_id VARCHAR(64),
    current_stay_id VARCHAR(64),
    last_cleaned TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_room_beds_room_id ON room_beds(room_id);
CREATE INDEX IF NOT EXISTS ix_room_beds_status ON room_beds(status);
CREATE INDEX IF NOT EXISTS ix_room_beds_current_patient_id ON room_beds(current_patient_id);

-- 4. Patients
CREATE TABLE IF NOT EXISTS patients (
    id VARCHAR(64) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    search_key VARCHAR(255),
    date_of_birth DATE NOT NULL,
    age INTEGER,
    gender VARCHAR(32) NOT NULL,
    contact_number VARCHAR(32) NOT NULL,
    emergency_contact VARCHAR(32) NOT NULL,
    emergency_contact_name VARCHAR(255) NOT NULL,
    medical_condition TEXT NOT NULL,
    allergies TEXT,
    blood_type VARCHAR(16),
    admission_date TIMESTAMPTZ NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    discharge_date TIMESTAMPTZ,
    exit_date TIMESTAMPTZ,
    room_id VARCHAR(64) REFERENCES rooms(id) ON DELETE SET NULL,
    room_number VARCHAR(32),
    floor INTEGER,
    bed_ids JSONB DEFAULT '[]'::jsonb,
    bed_labels JSONB DEFAULT '[]'::jsonb,
    lobby VARCHAR(64),
    address TEXT,
    registration_number VARCHAR(64) UNIQUE,
    registration_date TIMESTAMPTZ,
    pan_card_number VARCHAR(32),
    aadhaar_card_number VARCHAR(32),
    receipt_number VARCHAR(64),
    mode_of_payment VARCHAR(64),
    uti_number VARCHAR(64),
    payment_pending BOOLEAN DEFAULT FALSE,
    payment_status VARCHAR(32) DEFAULT 'Paid',
    total_paid_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    current_due_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    refund_due_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_refund_due_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_refunded_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    admission_balances JSONB NOT NULL DEFAULT '{}'::jsonb,
    payment_due_date TIMESTAMPTZ,
    is_advance_period BOOLEAN NOT NULL DEFAULT TRUE,
    advance_billed_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    billing_amount_override NUMERIC(12, 2),
    attendance_charges NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_present_days INTEGER NOT NULL DEFAULT 0,
    total_absent_days INTEGER NOT NULL DEFAULT 0,
    max_stay_days INTEGER NOT NULL DEFAULT 60,
    extension_approved BOOLEAN NOT NULL DEFAULT FALSE,
    extension_days INTEGER NOT NULL DEFAULT 0,
    extension_reason TEXT,
    approved_by VARCHAR(255),
    approved_date TIMESTAMPTZ,
    photo_data_url TEXT,
    photo_ref VARCHAR(255),
    photo_file_name VARCHAR(255),
    notes TEXT,
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_patients_full_name ON patients(full_name);
CREATE INDEX IF NOT EXISTS ix_patients_search_key ON patients(search_key);
CREATE INDEX IF NOT EXISTS ix_patients_status ON patients(status);
CREATE INDEX IF NOT EXISTS ix_patients_admission_date ON patients(admission_date);
CREATE INDEX IF NOT EXISTS ix_patients_registration_number ON patients(registration_number);
CREATE INDEX IF NOT EXISTS ix_patients_room_id ON patients(room_id);

-- 5. Patient Attendants
CREATE TABLE IF NOT EXISTS patient_attendants (
    id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    age VARCHAR(16),
    relation VARCHAR(64),
    aadhaar_number VARCHAR(32),
    mobile_number VARCHAR(32),
    is_emergency_contact BOOLEAN NOT NULL DEFAULT FALSE,
    photo_ref VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_patient_attendants_patient_id ON patient_attendants(patient_id);

-- 6. Stays
CREATE TABLE IF NOT EXISTS stays (
    id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    patient_name VARCHAR(255) NOT NULL,
    patient_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    room_id VARCHAR(64) NOT NULL REFERENCES rooms(id) ON DELETE RESTRICT,
    room_number VARCHAR(32) NOT NULL,
    room_type VARCHAR(32) NOT NULL,
    cycle_id VARCHAR(64),
    admission_date TIMESTAMPTZ NOT NULL,
    duration_days INTEGER NOT NULL,
    expected_discharge_date TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    expiry_date TIMESTAMPTZ NOT NULL,
    total_extended_days INTEGER NOT NULL DEFAULT 0,
    attendant_count INTEGER NOT NULL DEFAULT 0,
    attendant_labels JSONB NOT NULL DEFAULT '[]'::jsonb,
    daily_rate NUMERIC(12, 2),
    daily_rate_is_manual BOOLEAN NOT NULL DEFAULT FALSE,
    long_stay_daily_rate NUMERIC(12, 2),
    cost_override NUMERIC(12, 2),
    billing_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    total_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    base_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    extra_attendant_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    paid_amount NUMERIC(12, 2),
    pending_amount NUMERIC(12, 2),
    extensions JSONB NOT NULL DEFAULT '[]'::jsonb,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    bed_number INTEGER,
    bed_id VARCHAR(64) REFERENCES room_beds(id) ON DELETE SET NULL,
    bed_label VARCHAR(32),
    notes TEXT,
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_stays_patient_id ON stays(patient_id);
CREATE INDEX IF NOT EXISTS ix_stays_room_id ON stays(room_id);
CREATE INDEX IF NOT EXISTS ix_stays_status ON stays(status);
CREATE INDEX IF NOT EXISTS ix_stays_admission_date ON stays(admission_date);
CREATE INDEX IF NOT EXISTS ix_stays_expected_discharge ON stays(expected_discharge_date);

-- 7. Daily Attendance Records
CREATE TABLE IF NOT EXISTS attendance_records (
    id VARCHAR(128) PRIMARY KEY,
    kind VARCHAR(32) NOT NULL,
    attendance_date DATE NOT NULL,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_attendance_kind_date_patient ON attendance_records(kind, attendance_date, patient_id);
CREATE INDEX IF NOT EXISTS ix_attendance_patient_id ON attendance_records(patient_id);

-- 8. Payments & Billing Transactions
CREATE TABLE IF NOT EXISTS payments (
    id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    cycle_id VARCHAR(64),
    type VARCHAR(32) NOT NULL DEFAULT 'payment',
    amount NUMERIC(12, 2) NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    paid_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    pending_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    payment_status VARCHAR(32) NOT NULL DEFAULT 'Paid',
    method VARCHAR(32) NOT NULL DEFAULT 'cash',
    payment_date TIMESTAMPTZ NOT NULL,
    receipt_number VARCHAR(64),
    check_number VARCHAR(64),
    bank_name VARCHAR(128),
    transaction_id VARCHAR(128),
    source VARCHAR(32) NOT NULL DEFAULT 'manual',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_payments_patient_id ON payments(patient_id);
CREATE INDEX IF NOT EXISTS ix_payments_payment_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS ix_payments_receipt_number ON payments(receipt_number);

-- 9. Patient Photos (Base64 Binary Store)
CREATE TABLE IF NOT EXISTS patient_photos (
    photo_ref VARCHAR(255) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    photo_type VARCHAR(32) NOT NULL,
    content_type VARCHAR(64) NOT NULL,
    data TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_patient_photos_patient_id ON patient_photos(patient_id);

-- 10. System Sequence Counters
CREATE TABLE IF NOT EXISTS system_counters (
    counter_name VARCHAR(64) PRIMARY KEY,
    current_value BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 11. System Settings
CREATE TABLE IF NOT EXISTS system_settings (
    category VARCHAR(64) NOT NULL,
    settings_key VARCHAR(64) NOT NULL,
    settings_value JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (category, settings_key)
);

-- 12. Inventory Items
CREATE TABLE IF NOT EXISTS inventory_items (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(64) NOT NULL,
    unit VARCHAR(32) NOT NULL,
    min_stock_level DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    current_stock DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    created_by VARCHAR(64) NOT NULL,
    updated_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_inventory_items_name ON inventory_items(name);
CREATE INDEX IF NOT EXISTS ix_inventory_items_category ON inventory_items(category);

-- 13. Vendors
CREATE TABLE IF NOT EXISTS vendors (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone VARCHAR(32),
    email VARCHAR(255),
    address TEXT,
    category VARCHAR(64) NOT NULL DEFAULT 'General',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_vendors_name ON vendors(name);

-- 14. Purchases
CREATE TABLE IF NOT EXISTS purchases (
    id VARCHAR(64) PRIMARY KEY,
    vendor_id VARCHAR(64) REFERENCES vendors(id) ON DELETE SET NULL,
    vendor_name VARCHAR(255) NOT NULL,
    item_id VARCHAR(64) REFERENCES inventory_items(id) ON DELETE SET NULL,
    item_name VARCHAR(255) NOT NULL,
    quantity DOUBLE PRECISION NOT NULL,
    unit VARCHAR(32) NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL,
    purchase_date TIMESTAMPTZ NOT NULL,
    invoice_number VARCHAR(64),
    notes TEXT,
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_purchases_purchase_date ON purchases(purchase_date);

-- 15. Expense Entries
CREATE TABLE IF NOT EXISTS expense_entries (
    id VARCHAR(64) PRIMARY KEY,
    category VARCHAR(64) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    payment_method VARCHAR(32) NOT NULL DEFAULT 'cash',
    paid_to VARCHAR(255) NOT NULL,
    expense_date TIMESTAMPTZ NOT NULL,
    description TEXT,
    receipt_url VARCHAR(512),
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_expense_entries_expense_date ON expense_entries(expense_date);
CREATE INDEX IF NOT EXISTS ix_expense_entries_category ON expense_entries(category);

-- 16. Staff Salaries
CREATE TABLE IF NOT EXISTS salaries (
    id VARCHAR(64) PRIMARY KEY,
    staff_id VARCHAR(64) NOT NULL,
    staff_name VARCHAR(255) NOT NULL,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    base_salary NUMERIC(12, 2) NOT NULL,
    deductions NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    bonuses NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    net_salary NUMERIC(12, 2) NOT NULL,
    payment_date TIMESTAMPTZ,
    payment_method VARCHAR(32) NOT NULL DEFAULT 'bank_transfer',
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    notes TEXT
);
CREATE INDEX IF NOT EXISTS ix_salaries_staff_id ON salaries(staff_id);

-- 17. Sponsorships
CREATE TABLE IF NOT EXISTS sponsorships (
    id VARCHAR(64) PRIMARY KEY,
    sponsor_name VARCHAR(255) NOT NULL,
    patient_id VARCHAR(64) REFERENCES patients(id) ON DELETE SET NULL,
    patient_name VARCHAR(255),
    amount NUMERIC(12, 2) NOT NULL,
    sponsorship_date TIMESTAMPTZ NOT NULL,
    payment_method VARCHAR(32) NOT NULL DEFAULT 'bank_transfer',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_sponsorships_patient_id ON sponsorships(patient_id);
CREATE INDEX IF NOT EXISTS ix_sponsorships_sponsorship_date ON sponsorships(sponsorship_date);


-- Down Migration

DROP TABLE IF EXISTS sponsorships CASCADE;
DROP TABLE IF EXISTS salaries CASCADE;
DROP TABLE IF EXISTS expense_entries CASCADE;
DROP TABLE IF EXISTS purchases CASCADE;
DROP TABLE IF EXISTS vendors CASCADE;
DROP TABLE IF EXISTS inventory_items CASCADE;
DROP TABLE IF EXISTS system_settings CASCADE;
DROP TABLE IF EXISTS system_counters CASCADE;
DROP TABLE IF EXISTS patient_photos CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS attendance_records CASCADE;
DROP TABLE IF EXISTS stays CASCADE;
DROP TABLE IF EXISTS patient_attendants CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS room_beds CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS users CASCADE;
