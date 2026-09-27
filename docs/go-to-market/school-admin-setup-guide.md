# Enabling Tally at your school — Canvas administrator guide

Supports GO-LIVE **GL-01** (route b, per-school keys). The in-app "Request Tally at my school" flow links students' administrators to this guide. To be published at https://tally-app.dev (GL-02).

## What Tally is
Tally is an independent iOS app for students. It is not affiliated with Instructure. It shows a student's own courses, grades, deadlines and reminders. It reads only that student's data, using the student's own Canvas sign-in.

## Privacy and security summary
- Each student signs in on **your** Canvas sign-in page, using OAuth 2.0 + PKCE. Tally never receives passwords.
- **There is no Tally server.** Canvas data goes from your Canvas to the student's iPhone only, where it is stored encrypted and replaced on every refresh.
- Access is read-only, limited to the scopes below. Sign-out revokes the token.

## Create the developer key (about 5 minutes)
1. **Admin → Developer Keys → + Developer Key → API Key.**
2. Fill in the fields:
   - **Key Name:** Tally
   - **Owner Email:** your admin contact
   - **Redirect URIs:** `https://tally-app.dev/oauth/callback` — the Tally domain (GL-02).
   - **Client type: Public** (PKCE, no client secret). ⚠︎ *Whether your Canvas admin UI exposes this option is being verified (GL-05). If it does not, contact [[support e-mail]].*
3. **Enforce Scopes: ON.** Select only these:

   | Purpose | Scope |
   |---|---|
   | Student's name and personal calendar feed | `url:GET\|/api/v1/users/:user_id/profile` |
   | Courses and the student's scores | `url:GET\|/api/v1/courses` |
   | Assignments, weights and the student's submissions | `url:GET\|/api/v1/courses/:course_id/assignment_groups` |
   | Grading periods | `url:GET\|/api/v1/courses/:course_id/grading_periods` |
   | To-do and due items | `url:GET\|/api/v1/planner/items` |
   | Course calendar events | `url:GET\|/api/v1/calendar_events` |
   | Announcements | `url:GET\|/api/v1/announcements` |
   | Course colours | `url:GET\|/api/v1/users/:id/colors` |

   *These scope strings come from Instructure's API docs as read on 2026-09-26. Confirm them against the scope picker in your Canvas version.*
4. **Save**, then switch the key's state to **ON**.
5. Send the **Client ID** (the numeric key ID, which is not secret) to [[support e-mail]]. We add your school to Tally's institution directory, and students can connect from then on.

## Turning Tally off
Set the key to **OFF**. Every Tally token for your school stops working immediately.
