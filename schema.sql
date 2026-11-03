-- ==============================================================================
-- Cocoa 🥥 - PostgreSQL Schema for Supabase
-- Run this script in your Supabase SQL Editor (https://supabase.com/dashboard/project/_/sql)
-- ==============================================================================

-- 1. Enable UUID generator
create extension if not exists "uuid-ossp";

-- 2. Create Tasks Table
create table if not exists public.tasks (
    id uuid primary key default uuid_generate_v4(),
    title text not null,
    notes text default '',
    estimated_minutes int default 25,
    time_spent_seconds int default 0,
    is_completed boolean default false,
    board text default 'Today', -- 'Backlog', 'Upcoming', 'Today', 'Completed'
    priority text default 'Medium', -- 'Low', 'Medium', 'High'
    list_name text default 'General',
    completed_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- 3. Create Subtasks Table
create table if not exists public.subtasks (
    id uuid primary key default uuid_generate_v4(),
    task_id uuid references public.tasks(id) on delete cascade,
    title text not null,
    is_completed boolean default false,
    created_at timestamp with time zone default now()
);

-- 4. Create Indexes for High Performance
create index if not exists idx_tasks_board on public.tasks(board);
create index if not exists idx_tasks_list on public.tasks(list_name);
create index if not exists idx_subtasks_task on public.subtasks(task_id);

-- 5. Enable Row Level Security (RLS)
alter table public.tasks enable row level security;
alter table public.subtasks enable row level security;

-- 6. Default open policy for client anon key (can be restricted to auth.uid() if user login is used)
create policy "Allow all actions for anon users"
on public.tasks for all
using (true)
with check (true);

create policy "Allow all actions for anon users on subtasks"
on public.subtasks for all
using (true)
with check (true);
