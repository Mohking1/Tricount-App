-- Personal Expense Tracker Schema

-- Table for personal transactions (both income and expense)
CREATE TABLE IF NOT EXISTS personal_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  payment_mode TEXT NOT NULL CHECK (payment_mode IN ('cash', 'online')),
  category TEXT NOT NULL,
  date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  notes TEXT,
  photo_url TEXT,
  tricount_expense_id UUID, -- Link to group expense if auto-added
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Table to track cash and online balances
CREATE TABLE IF NOT EXISTS personal_balances (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  cash_balance NUMERIC DEFAULT 0,
  online_balance NUMERIC DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_personal_transactions_user_id ON personal_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_personal_transactions_date ON personal_transactions(date DESC);
CREATE INDEX IF NOT EXISTS idx_personal_transactions_type ON personal_transactions(type);
CREATE INDEX IF NOT EXISTS idx_personal_transactions_category ON personal_transactions(category);

-- Row Level Security
ALTER TABLE personal_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE personal_balances ENABLE ROW LEVEL SECURITY;

-- Policies for personal_transactions
CREATE POLICY "Users can view their own transactions"
  ON personal_transactions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transactions"
  ON personal_transactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own transactions"
  ON personal_transactions FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own transactions"
  ON personal_transactions FOR DELETE
  USING (auth.uid() = user_id);

-- Policies for personal_balances
CREATE POLICY "Users can view their own balance"
  ON personal_balances FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own balance"
  ON personal_balances FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own balance"
  ON personal_balances FOR UPDATE
  USING (auth.uid() = user_id);

-- Function to update balance after transaction
CREATE OR REPLACE FUNCTION update_personal_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Initialize balance if not exists
  INSERT INTO personal_balances (user_id, cash_balance, online_balance)
  VALUES (NEW.user_id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Update balance based on transaction type and payment mode
  IF NEW.payment_mode = 'cash' THEN
    IF NEW.type = 'income' THEN
      UPDATE personal_balances 
      SET cash_balance = cash_balance + NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    ELSE -- expense
      UPDATE personal_balances 
      SET cash_balance = cash_balance - NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    END IF;
  ELSE -- online
    IF NEW.type = 'income' THEN
      UPDATE personal_balances 
      SET online_balance = online_balance + NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    ELSE -- expense
      UPDATE personal_balances 
      SET online_balance = online_balance - NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update balance after insert
CREATE TRIGGER trigger_update_balance_after_insert
AFTER INSERT ON personal_transactions
FOR EACH ROW
EXECUTE FUNCTION update_personal_balance();

-- Function to handle balance updates when transaction is updated
CREATE OR REPLACE FUNCTION revert_and_update_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Revert old transaction
  IF OLD.payment_mode = 'cash' THEN
    IF OLD.type = 'income' THEN
      UPDATE personal_balances 
      SET cash_balance = cash_balance - OLD.amount
      WHERE user_id = OLD.user_id;
    ELSE
      UPDATE personal_balances 
      SET cash_balance = cash_balance + OLD.amount
      WHERE user_id = OLD.user_id;
    END IF;
  ELSE
    IF OLD.type = 'income' THEN
      UPDATE personal_balances 
      SET online_balance = online_balance - OLD.amount
      WHERE user_id = OLD.user_id;
    ELSE
      UPDATE personal_balances 
      SET online_balance = online_balance + OLD.amount
      WHERE user_id = OLD.user_id;
    END IF;
  END IF;

  -- Apply new transaction
  IF NEW.payment_mode = 'cash' THEN
    IF NEW.type = 'income' THEN
      UPDATE personal_balances 
      SET cash_balance = cash_balance + NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    ELSE
      UPDATE personal_balances 
      SET cash_balance = cash_balance - NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    END IF;
  ELSE
    IF NEW.type = 'income' THEN
      UPDATE personal_balances 
      SET online_balance = online_balance + NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    ELSE
      UPDATE personal_balances 
      SET online_balance = online_balance - NEW.amount, updated_at = NOW()
      WHERE user_id = NEW.user_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for updates
CREATE TRIGGER trigger_update_balance_after_update
AFTER UPDATE ON personal_transactions
FOR EACH ROW
EXECUTE FUNCTION revert_and_update_balance();

-- Function to handle balance when transaction is deleted
CREATE OR REPLACE FUNCTION revert_balance_on_delete()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.payment_mode = 'cash' THEN
    IF OLD.type = 'income' THEN
      UPDATE personal_balances 
      SET cash_balance = cash_balance - OLD.amount, updated_at = NOW()
      WHERE user_id = OLD.user_id;
    ELSE
      UPDATE personal_balances 
      SET cash_balance = cash_balance + OLD.amount, updated_at = NOW()
      WHERE user_id = OLD.user_id;
    END IF;
  ELSE
    IF OLD.type = 'income' THEN
      UPDATE personal_balances 
      SET online_balance = online_balance - OLD.amount, updated_at = NOW()
      WHERE user_id = OLD.user_id;
    ELSE
      UPDATE personal_balances 
      SET online_balance = online_balance + OLD.amount, updated_at = NOW()
      WHERE user_id = OLD.user_id;
    END IF;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger for deletes
CREATE TRIGGER trigger_update_balance_after_delete
AFTER DELETE ON personal_transactions
FOR EACH ROW
EXECUTE FUNCTION revert_balance_on_delete();
