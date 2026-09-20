# Lane iOS compatible backend

A small backend for the iOS port in this repository. It does **not** reproduce Lane's protected production request-signature mechanism.

It provides:

- Telegram-only sign in using a Telegram bot you control.
- JWT bearer sessions.
- Music search and 30-second previews through Apple's public iTunes Search API.
- Home/recent tracks.
- User profiles.
- Playlists.
- Friends/following.
- Track comments.
- Notifications and import placeholders.
- Optional `X-API-Key` style protection for your own deployment.

## Environment

Copy `.env.example` values into your hosting provider.

Required for Telegram login:

- `PUBLIC_BASE_URL`: public HTTPS URL of this backend.
- `AUTH_SECRET`: a long random value used for session tokens.
- `TELEGRAM_BOT_TOKEN`: token created with BotFather.
- `TELEGRAM_BOT_USERNAME`: bot username without @.
- `TELEGRAM_WEBHOOK_SECRET`: a random URL-safe value.

Optional:

- `LANE_API_KEY`: if set, all API calls except health/config/webhook must include this value in `X-API-Key`.
- `DATA_FILE`: persistent JSON database path. Mount a persistent volume for production use.

The server automatically calls Telegram `setWebhook` at startup when the required Telegram variables and `PUBLIC_BASE_URL` are present.

## iPhone app

In Lane iOS:

1. Profile → Advanced / API.
2. Mode → **Custom backend**.
3. Base URL → your deployed HTTPS URL.
4. If `LANE_API_KEY` is configured, enter header `X-API-Key` and its value.
5. Save.
6. Sign in with Telegram.

The app retrieves the Telegram bot username from `/config`, opens the bot with `/start auth<device-id>`, and polls `/auth/<device-id>` for the JWT.
