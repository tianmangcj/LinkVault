delete from transfer_tasks;

alter table transfer_tasks add column device_id uuid not null;

drop index if exists idx_transfer_tasks_user_direction_status;
create index idx_transfer_tasks_user_device_direction_status
    on transfer_tasks(user_id, device_id, direction, status, hidden_at);
create index idx_transfer_tasks_user_device_source
    on transfer_tasks(user_id, device_id, source_id);
