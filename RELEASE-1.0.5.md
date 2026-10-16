# Saleo Windows 1.0.5+14

Windows-only update. Android and the backend were not changed.

- Receipt Reveal (approved concept B) artwork and shared rounded Poppins layout for splash, welcome, company lookup, member login, registration, verification, PIN setup, company creation and recovery.
- Dedicated company-ID recovery, admin-PIN reset and staff-PIN help screens, with input validation and explicit success/failure states.
- Device light/dark mode before authentication. Signed-in appearance continues to use the existing user-scoped saved preferences and server synchronization.
- Distinct lightweight native vector graphics for all main sidebar destinations, using theme accent and foreground colours rather than fixed-colour image icons.
- Company-data loading uses the same receipt-themed presentation. No artificial startup delay or runtime artwork download.

Validation: 89 automated tests passed; targeted static analysis reported no issues. Tests use fake authentication responses and do not send real recovery emails. Live email delivery and cross-device preference restoration were not retested against production.

Packaging: the executable requires the adjacent DLLs and data folder. Keep the entire extracted package together. Existing company data is stored separately and is not part of the distribution archive.

Artwork: assets/branding/receipt-reveal.png, generated from the approved B reference. Prompt direction: transparent silver/graphite thermal receipt printer with a long curling paper receipt, restrained studio lighting, no embedded UI or labels. Native text and controls remain editable in the Flutter source.
