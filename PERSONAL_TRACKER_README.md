# Personal Expense Tracker Setup

## Database Setup

To enable the personal expense tracker feature, you need to run the SQL schema in your Supabase project:

1. Go to your Supabase Dashboard
2. Navigate to the SQL Editor
3. Copy and paste the contents of `supabase_personal_expenses.sql`
4. Run the SQL script

This will create:
- `personal_transactions` table for tracking income and expenses
- `personal_balances` table for tracking cash and online balances
- Automatic triggers to update balances when transactions are added/modified/deleted
- Row-level security policies to ensure users can only access their own data

## Features

### Personal Expense Tracker
- **Dual Balance Tracking**: Separate tracking for Cash and Online balances
- **Income & Expense**: Record both income and expenses
- **Custom Categories**: Same category system as group expenses
- **Payment Modes**: Track whether payment was made via Cash or Online
- **Auto-Sync**: Group expenses automatically sync to personal tracker
- **Insights**: Visual analytics including:
  - Total income, expense, and balance summary
  - Category-wise pie chart
  - Monthly trends
  - Top spending categories

### Navigation
- Access Personal Tracker from the new "Personal" tab in the bottom navigation bar
- 4 tabs: Tricounts | Personal | Requests | Profile

### Transaction Management
- Add transactions with:
  - Type (Income/Expense)
  - Amount
  - Payment Mode (Cash/Online)
  - Category
  - Date
  - Optional notes and photos
- View transaction history with filtering
- Delete transactions
- Automatic balance updates

### Auto-Sync from Group Expenses
When you create a group expense where you are the payer:
- The expense is automatically added to your personal tracker
- It's marked as an expense with the same amount, category, and payment method
- This helps you track your total spending across both personal and group contexts
- The balance (cash or online) is automatically reduced

## Notes

- All balances are automatically calculated based on transactions
- The system uses database triggers to ensure balance accuracy
- Each user's data is isolated using Row Level Security (RLS)
- Transactions are sorted by date (most recent first)
