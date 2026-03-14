-- Add email column to public.users
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email text;

-- Create index for fast email lookup
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users (email);

-- Backfill email from auth.users for existing users
UPDATE public.users
SET email = au.email
FROM auth.users au
WHERE public.users.id = au.id
  AND public.users.email IS NULL;

-- Update the trigger function to also copy email on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, name, photo_url, email)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'name',
    new.raw_user_meta_data->>'photo_url',
    new.email
  );
  RETURN new;
END;
$$;

-- RPC function: search user by email (case-insensitive)
CREATE OR REPLACE FUNCTION public.find_user_by_email(search_email text)
RETURNS SETOF public.users
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.users WHERE lower(email) = lower(search_email) LIMIT 1;
$$;
