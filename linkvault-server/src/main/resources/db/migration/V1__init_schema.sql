create table users (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    username varchar(64) not null unique,
    email varchar(160) unique,
    password_hash varchar(120) not null,
    display_name varchar(80) not null,
    avatar_text varchar(4) not null,
    role varchar(24) not null,
    status varchar(24) not null
);

create table refresh_tokens (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    device_id uuid not null,
    token_hash varchar(96) not null unique,
    expires_at timestamp with time zone not null,
    revoked_at timestamp with time zone
);

create table captcha_challenges (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    code_hash varchar(96) not null,
    image_base64 varchar(4096) not null,
    expires_at timestamp with time zone not null,
    used_at timestamp with time zone
);

create table devices (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    device_name varchar(120) not null,
    platform varchar(24) not null,
    app_version varchar(40),
    last_ip varchar(80),
    last_seen_at timestamp with time zone not null,
    revoked_at timestamp with time zone
);

create table user_quotas (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null unique,
    total_bytes bigint not null,
    used_bytes bigint not null
);

create table file_nodes (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    parent_id uuid,
    storage_object_id uuid,
    name varchar(255) not null,
    type varchar(24) not null,
    status varchar(24) not null,
    size_bytes bigint not null,
    mime_type varchar(160),
    sha256 varchar(64),
    recycled_at timestamp with time zone,
    purged_at timestamp with time zone
);

create table storage_objects (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    bucket varchar(120) not null,
    object_key varchar(420) not null unique,
    sha256 varchar(64) not null,
    size_bytes bigint not null,
    mime_type varchar(160),
    reference_count bigint not null,
    pending_delete_at timestamp with time zone
);

create table upload_tasks (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    parent_id uuid,
    file_name varchar(255) not null,
    size_bytes bigint not null,
    mime_type varchar(160),
    sha256 varchar(64) not null,
    object_key varchar(420) not null,
    status varchar(24) not null,
    transferred_bytes bigint not null,
    completed_at timestamp with time zone
);

create table folder_upload_tasks (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    parent_id uuid,
    folder_name varchar(255) not null,
    file_count integer not null,
    total_bytes bigint not null,
    status varchar(24) not null
);

create table transfer_tasks (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    direction varchar(24) not null,
    task_type varchar(24) not null,
    source_id uuid not null,
    title varchar(255) not null,
    total_bytes bigint not null,
    transferred_bytes bigint not null,
    status varchar(24) not null,
    failure_reason varchar(500),
    completed_at timestamp with time zone,
    hidden_at timestamp with time zone
);

create table download_tasks (
    id uuid primary key,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    version bigint not null,
    user_id uuid not null,
    file_id uuid not null,
    file_name varchar(255) not null,
    size_bytes bigint not null,
    downloaded_bytes bigint not null,
    status varchar(24) not null,
    completed_at timestamp with time zone
);

create index idx_refresh_tokens_user_device on refresh_tokens(user_id, device_id);
create index idx_devices_user on devices(user_id);
create index idx_file_nodes_user_parent_status on file_nodes(user_id, parent_id, status);
create index idx_file_nodes_user_status_name on file_nodes(user_id, status, name);
create index idx_storage_objects_dedup on storage_objects(sha256, size_bytes, pending_delete_at);
create index idx_upload_tasks_user on upload_tasks(user_id);
create index idx_transfer_tasks_user_direction_status on transfer_tasks(user_id, direction, status, hidden_at);
create index idx_transfer_tasks_user_source on transfer_tasks(user_id, source_id);
create index idx_download_tasks_user on download_tasks(user_id);
