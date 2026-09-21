# Context Lens 0.2 Beta setup

## 1. Enable the Supabase schema

1. Open the Supabase project dashboard.
2. Open **SQL Editor** and create a new query.
3. Paste the complete contents of `supabase/migrations/001_context_lens.sql`.
4. Select **Run**. The script is idempotent and can safely be run again.
5. Then run `supabase/migrations/002_word_meanings.sql` for word-level meanings and review scheduling.

The migration creates `profiles`, `study_contexts`, and `study_words`. Row Level
Security is enabled on every user table; signed-in users can only read and write
rows whose `user_id` matches their own account.

## 2. Authentication

Email/password authentication is already enabled in this Supabase project and
email confirmation is required. A new user must click the verification link
before the first login.

## 3. Mac beta

Build with `macos/ContextLens/build.sh`. In the menu bar use **账户与同步** to
register or sign in. Existing local collections can then be uploaded with
**立即同步**. The user's DeepSeek key remains device-local.

The local build is ad-hoc signed. Replacing it can invalidate the macOS Accessibility permission. Remove the old entry and add the newly built app again under **System Settings → Privacy & Security → Accessibility**. Public releases must use a stable Developer ID signature.

## 4. Android beta

Install Android Studio, open the `android` directory, allow Gradle sync to
complete, create an Android 14+ emulator, and run the `app` configuration.
The Android client provides account access, synchronized review, and free
dictionary lookup with local response caching. It never calls DeepSeek.

Release signing, an offline licensed bilingual dictionary dataset, account deletion, and store metadata remain release blockers; see `RELEASE_CHECKLIST.md`.
