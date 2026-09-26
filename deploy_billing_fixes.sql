\set ON_ERROR_STOP on

\echo '1/7 - Fixing the pre-existing sale-order trigger ambiguity'
\ir fix_sale_order_trigger_ambiguity.sql

\echo '2/7 - Migrating account_move states and balances'
\ir account_move_new_types_migration.sql

\echo '3/7 - Installing sale-order to invoice flow'
\ir vps_sale_order_invoice_flow.sql

\echo '4/7 - Installing sale-order executor function'
\ir fnc_sale_order.sql

\echo '5/7 - Installing account-move executor function'
\ir fnc_account_move.sql

\echo '6/7 - Installing and repairing payment linking'
\ir payment_invoice_link_fix.sql

\echo '7/7 - Installing and repairing credit-note reversal logic'
\ir credit_note_reversal_fix.sql

\echo 'Billing fixes installed successfully'
