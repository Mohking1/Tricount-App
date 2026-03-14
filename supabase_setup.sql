-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Create users table (public profile)
create table public.users (
  id uuid references auth.users not null primary key,
  name text,
  photo_url text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security (RLS)
alter table public.users enable row level security;

-- Create policies for users
create policy "Public profiles are viewable by everyone."
  on users for select
  using ( true );

create policy "Users can insert their own profile."
  on users for insert
  with check ( auth.uid() = id );

create policy "Users can update own profile."
  on users for update
  using ( auth.uid() = id );

-- Function to handle new user signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.users (id, name, photo_url)
  values (new.id, new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'photo_url');
  return new;
end;
$$;

-- Trigger to automatically create public user profile
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Create tricounts table
create table public.tricounts (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  description text,
  created_by uuid references public.users(id),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  participant_ids uuid[] default '{}',
  participants jsonb default '[]',
  emoji text
);

-- Enable RLS for tricounts
alter table public.tricounts enable row level security;

-- Policies for tricounts
create policy "Users can view tricounts they are part of."
  on tricounts for select
  using ( auth.uid() = any(participant_ids) );

create policy "Users can insert tricounts."
  on tricounts for insert
  with check ( auth.uid() = created_by );

create policy "Users can update tricounts they are part of."
  on tricounts for update
  using ( auth.uid() = any(participant_ids) );

-- Create expenses table
create table public.expenses (
  id uuid default uuid_generate_v4() primary key,
  tricount_id uuid references public.tricounts(id) on delete cascade,
  name text not null,
  paid_by text,
  user_id uuid references public.users(id),
  value numeric not null default 0,
  photo_url text,
  category text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  involved_participants jsonb default '[]',
  type text default 'expense'
);

-- Enable RLS for expenses
alter table public.expenses enable row level security;

-- Policies for expenses
create policy "Users can view expenses of tricounts they belong to."
  on expenses for select
  using (
    exists (
      select 1 from tricounts
      where tricounts.id = expenses.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

create policy "Users can insert expenses to tricounts they belong to."
  on expenses for insert
  with check (
    exists (
      select 1 from tricounts
      where tricounts.id = expenses.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

create policy "Users can update expenses of tricounts they belong to."
  on expenses for update
  using (
    exists (
      select 1 from tricounts
      where tricounts.id = expenses.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

-- Create tricount_invites table
create table public.tricount_invites (
  id uuid default uuid_generate_v4() primary key,
  tricount_id uuid references public.tricounts(id) on delete cascade,
  tricount_name text,
  invited_by text,
  user_id uuid references public.users(id),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for invites
alter table public.tricount_invites enable row level security;

-- Policies for invites
create policy "Users can view their invites."
  on tricount_invites for select
  using ( auth.uid() = user_id );

create policy "Users can insert invites."
  on tricount_invites for insert
  with check ( true ); -- Ideally check if sender is part of tricount

create policy "Users can delete their invites."
  on tricount_invites for delete
  using ( auth.uid() = user_id );

-- Create friends table
create table public.friends (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.users(id),
  friend_id uuid references public.users(id),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id, friend_id)
);

-- Enable RLS for friends
alter table public.friends enable row level security;

-- Policies for friends
create policy "Users can view their friends."
  on friends for select
  using ( auth.uid() = user_id );

create policy "Users can add friends."
  on friends for insert
  with check ( auth.uid() = user_id );

-- Create friend_requests table
create table public.friend_requests (
  id uuid default uuid_generate_v4() primary key,
  sender_id uuid references public.users(id),
  receiver_id uuid references public.users(id),
  status text default 'pending',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(sender_id, receiver_id)
);

-- Enable RLS for friend_requests
alter table public.friend_requests enable row level security;

-- Policies for friend_requests
create policy "Users can view requests they sent or received."
  on friend_requests for select
  using ( auth.uid() = sender_id or auth.uid() = receiver_id );

create policy "Users can send friend requests."
  on friend_requests for insert
  with check ( auth.uid() = sender_id );

create policy "Users can delete requests they sent or received."
  on friend_requests for delete
  using ( auth.uid() = sender_id or auth.uid() = receiver_id );

-- Storage buckets setup (You need to create these in the Supabase dashboard)
-- Bucket: 'expenses' (public)
-- Bucket: 'profiles' (public)

-- Migration: Add category to expenses
do $$
begin
    if not exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'category') then
        alter table public.expenses add column category text;
    end if;
end $$;

-- Migrations (Run these if tables already exist)
do $$
begin
    if not exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'involved_participants') then
        alter table public.expenses add column involved_participants jsonb default '[]';
    end if;
    
    if not exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'type') then
        alter table public.expenses add column type text default 'expense';
    end if;

    if not exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'payment_method') then
        alter table public.expenses add column payment_method text default 'Online';
    end if;

    if not exists (select 1 from information_schema.columns where table_name = 'tricounts' and column_name = 'emoji') then
        alter table public.tricounts add column emoji text;
    end if;
    
    if not exists (select 1 from information_schema.columns where table_name = 'categories' and column_name = 'icon') then
        alter table public.categories add column icon text;
    end if;
end $$;

-- Create categories table
create table public.categories (
  id uuid default uuid_generate_v4() primary key,
  tricount_id uuid references public.tricounts(id) on delete cascade,
  name text not null,
  icon text,
  color text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for categories
alter table public.categories enable row level security;

-- Policies for categories
create policy "Users can view categories of tricounts they belong to."
  on categories for select
  using (
    exists (
      select 1 from tricounts
      where tricounts.id = categories.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

create policy "Users can insert categories to tricounts they belong to."
  on categories for insert
  with check (
    exists (
      select 1 from tricounts
      where tricounts.id = categories.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

create policy "Users can delete categories of tricounts they belong to."
  on categories for delete
  using (
    exists (
      select 1 from tricounts
      where tricounts.id = categories.tricount_id
      and auth.uid() = any(tricounts.participant_ids)
    )
  );

-- Migration: Drop foreign key constraint on expenses.user_id to allow ghost users
alter table public.expenses drop constraint if exists expenses_user_id_fkey;

