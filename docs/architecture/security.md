# ACOMS Security Architecture

## Principles
Least privilege, defense in depth, server-side authorization, RLS, secure authentication, auditability, protected secrets, secure files and safe errors.

## Capabilities
view_inventory; create_transfer; approve_transfer; dispatch_transfer; receive_transfer; reconcile_transfer; report_damage; confirm_loss; manage_catalogue; manage_users; view_reports; manage_configuration.

## Station Scoping
Station users access only permitted station data and actions. Cross-station operations require explicit capability.

## Audit
Audit transfers, approvals, dispatch, receiving, reconciliation, inventory transactions, damage, loss, catalogue changes and permission changes.

## Files
Private attachments require controlled access; do not expose predictable public URLs.

## Secrets
Never commit passwords, production credentials, service-role keys or private tokens.
