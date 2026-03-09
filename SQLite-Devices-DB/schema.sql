PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS devices (
    device_pk INTEGER PRIMARY KEY,
    public_device_record_key TEXT UNIQUE,
    public_version_status TEXT,
    device_record_status TEXT,
    public_version_number INTEGER,
    public_version_date TEXT,
    device_publish_date TEXT,
    device_comm_distribution_end_date TEXT,
    device_comm_distribution_status TEXT,
    brand_name TEXT,
    version_model_number TEXT,
    catalog_number TEXT,
    duns_number TEXT,
    company_name TEXT,
    device_count INTEGER,
    device_description TEXT,
    dm_exempt INTEGER,
    premarket_exempt INTEGER,
    device_hctp INTEGER,
    device_kit INTEGER,
    device_combination_product INTEGER,
    single_use INTEGER,
    lot_batch INTEGER,
    serial_number INTEGER,
    manufacturing_date INTEGER,
    expiration_date INTEGER,
    donation_id_number INTEGER,
    labeled_contains_nrl INTEGER,
    labeled_no_nrl INTEGER,
    mri_safety_status TEXT,
    rx INTEGER,
    otc INTEGER
);

CREATE TABLE IF NOT EXISTS identifiers (
    identifier_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    device_id TEXT,
    device_id_type TEXT,
    device_id_issuing_agency TEXT,
    contains_di_number TEXT,
    pkg_quantity TEXT,
    pkg_discontinue_date TEXT,
    pkg_status TEXT,
    pkg_type TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE TABLE IF NOT EXISTS contacts (
    contact_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    contact_type TEXT,
    phone TEXT,
    phone_extension TEXT,
    email TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE TABLE IF NOT EXISTS gmdn_terms (
    gmdn_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    gmdn_code TEXT,
    gmdn_pt_name TEXT,
    gmdn_pt_definition TEXT,
    implantable INTEGER,
    gmdn_code_status TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE TABLE IF NOT EXISTS product_codes (
    product_code_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    product_code TEXT,
    product_code_name TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE TABLE IF NOT EXISTS device_sizes (
    device_size_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    size_type TEXT,
    size_value TEXT,
    size_unit TEXT,
    size_text TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE TABLE IF NOT EXISTS sterilization_methods (
    sterilization_method_pk INTEGER PRIMARY KEY,
    device_fk INTEGER NOT NULL,
    method_name TEXT,
    FOREIGN KEY (device_fk) REFERENCES devices(device_pk)
);

CREATE INDEX IF NOT EXISTS idx_devices_catalog_number
    ON devices(catalog_number);

CREATE INDEX IF NOT EXISTS idx_devices_company_name
    ON devices(company_name);

CREATE INDEX IF NOT EXISTS idx_devices_distribution_status
    ON devices(device_comm_distribution_status);

CREATE INDEX IF NOT EXISTS idx_identifiers_device_fk
    ON identifiers(device_fk);

CREATE INDEX IF NOT EXISTS idx_identifiers_agency
    ON identifiers(device_id_issuing_agency);

CREATE INDEX IF NOT EXISTS idx_identifiers_type
    ON identifiers(device_id_type);

CREATE INDEX IF NOT EXISTS idx_identifiers_device_id
    ON identifiers(device_id);

CREATE INDEX IF NOT EXISTS idx_product_codes_device_fk
    ON product_codes(device_fk);

CREATE INDEX IF NOT EXISTS idx_product_codes_code
    ON product_codes(product_code);
