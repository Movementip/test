import express from "express";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const app = express();
app.use(express.json({ limit: "1mb" }));

const PORT = Number(process.env.PORT || 3000);
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "").replace(/\/$/, "");
const AUTH_SECRET = process.env.AUTH_SECRET || "development-only-change-me";
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || "";
const TELEGRAM_BOT_USERNAME = (process.env.TELEGRAM_BOT_USERNAME || "").replace(/^@/, "");
const TELEGRAM_WEBHOOK_SECRET = process.env.TELEGRAM_WEBHOOK_SECRET || "lane-webhook";
const LANE_API_KEY = process.env.LANE_API_KEY || "";
const DATA_FILE = path.resolve(process.env.DATA_FILE || "./data/lane.json");

fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });

function blankDB() {
  return {
    users: {},
    pendingAuth: {},
    playlists: {},
    follows: {},
    comments: {},
    recent: {},
    notifications: {}
  };
}

function loadDB() {
  try {
    return { ...blankDB(), ...JSON.parse(fs.readFileSync(DATA_FILE, "utf8")) };
  } catch {
    return blankDB();
  }
}

let db = loadDB();

function saveDB() {
  const tmp = DATA_FILE + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2));
  fs.renameSync(tmp, DATA_FILE);
}

function b64url(input) {
  return Buffer.from(input).toString("base64url");
}

function issueToken(user) {
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(JSON.stringify({
    sub: user.laneId,
    tg: user.telegramId,
    iat: now,
    exp: now + 60 * 60 * 24 * 90
  }));
  const signature = crypto
    .createHmac("sha256", AUTH_SECRET)
    .update(header + "." + payload)
    .digest("base64url");
  return header + "." + payload + "." + signature;
}

function verifyToken(token) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) return null;
  const expected = crypto
    .createHmac("sha256", AUTH_SECRET)
    .update(parts[0] + "." + parts[1])
    .digest("base64url");

  const a = Buffer.from(parts[2]);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (!payload.sub || (payload.exp && payload.exp < Math.floor(Date.now() / 1000))) return null;
    return payload;
  } catch {
    return null;
  }
}

function apiKeyMiddleware(req, res, next) {
  if (!LANE_API_KEY) return next();
  if (req.path === "/health" || req.path === "/config" || req.path.startsWith("/telegram/webhook/")) return next();
  const incoming = req.get("X-API-Key") || "";
  if (incoming !== LANE_API_KEY) return res.status(401).json({ code: "INVALID_API_KEY", message: "Invalid API key" });
  next();
}

function authMiddleware(req, res, next) {
  const token = (req.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const payload = verifyToken(token);
  if (!payload) return res.status(401).json({ code: "UNAUTHORIZED", message: "Bearer token required" });
  const user = db.users[payload.sub];
  if (!user) return res.status(401).json({ code: "UNKNOWN_USER", message: "User no longer exists" });
  req.user = user;
  next();
}

app.use(apiKeyMiddleware);

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "lane-ios-backend", time: new Date().toISOString() });
});

app.get("/config", (_req, res) => {
  res.json({
    service: "lane-ios-backend",
    auth: "telegram",
    telegramBotUsername: TELEGRAM_BOT_USERNAME,
    apiKeyRequired: Boolean(LANE_API_KEY),
    musicProvider: "itunes-preview"
  });
});

app.get("/time", (_req, res) => res.json({ unix: Date.now(), iso: new Date().toISOString() }));

async function telegramCall(method, body) {
  if (!TELEGRAM_BOT_TOKEN) throw new Error("TELEGRAM_BOT_TOKEN is not configured");
  const response = await fetch("https://api.telegram.org/bot" + TELEGRAM_BOT_TOKEN + "/" + method, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  const json = await response.json();
  if (!json.ok) throw new Error("Telegram " + method + ": " + JSON.stringify(json));
  return json.result;
}

async function setupTelegramWebhook() {
  if (!TELEGRAM_BOT_TOKEN || !PUBLIC_BASE_URL || !TELEGRAM_WEBHOOK_SECRET) return;
  const url = PUBLIC_BASE_URL + "/telegram/webhook/" + encodeURIComponent(TELEGRAM_WEBHOOK_SECRET);
  try {
    await telegramCall("setWebhook", {
      url,
      allowed_updates: ["message"],
      drop_pending_updates: false
    });
    console.log("Telegram webhook configured:", url);
  } catch (error) {
    console.error("Telegram webhook setup failed:", error.message);
  }
}

function normalizeStartText(text = "") {
  const first = String(text).trim().split(/\s+/)[0] || "";
  return first.replace(/^\/start(?:@[A-Za-z0-9_]+)?\s*/i, "");
}

app.post("/telegram/webhook/:secret", async (req, res) => {
  if (req.params.secret !== TELEGRAM_WEBHOOK_SECRET) return res.sendStatus(404);
  res.sendStatus(200);

  try {
    const message = req.body?.message;
    if (!message?.from) return;

    const text = String(message.text || "");
    const match = text.match(/^\/start(?:@[A-Za-z0-9_]+)?\s+auth([0-9a-fA-F]{8,64})$/);
    if (!match) return;

    const authId = match[1].toLowerCase();
    const tg = message.from;
    const existing = Object.values(db.users).find(u => String(u.telegramId) === String(tg.id));

    const laneId = existing?.laneId || crypto.randomUUID();
    const user = {
      laneId,
      telegramId: Number(tg.id),
      displayedName: [tg.first_name, tg.last_name].filter(Boolean).join(" ") || tg.username || "Telegram user",
      userName: tg.username || "",
      avatarUrl: existing?.avatarUrl || "",
      headerUrl: existing?.headerUrl || "",
      statusText: existing?.statusText || "",
      premiumExpiresIn: 0,
      countryCode: existing?.countryCode || "",
      createdAt: existing?.createdAt || Date.now(),
      updatedAt: Date.now()
    };

    db.users[laneId] = user;
    db.pendingAuth[authId] = {
      token: issueToken(user),
      laneId,
      createdAt: Date.now(),
      consumed: false
    };
    saveDB();

    await telegramCall("sendMessage", {
      chat_id: message.chat.id,
      text: "Authorization successful. Return to Lane on your iPhone."
    });
  } catch (error) {
    console.error("Telegram webhook error:", error);
  }
});

app.get("/auth/:authId", (req, res) => {
  const authId = String(req.params.authId || "").toLowerCase();
  const pending = db.pendingAuth[authId];

  if (!pending) return res.status(202).json({ status: "pending" });
  if (Date.now() - pending.createdAt > 15 * 60 * 1000) {
    delete db.pendingAuth[authId];
    saveDB();
    return res.status(410).json({ status: "expired" });
  }

  pending.consumed = true;
  saveDB();
  res.json({ token: pending.token, isFirstAuth: false });
});

function publicUser(user, viewerLaneId = null) {
  const followers = Object.entries(db.follows).filter(([, list]) => Array.isArray(list) && list.includes(user.laneId)).length;
  const following = (db.follows[user.laneId] || []).length;
  return {
    displayedName: user.displayedName,
    premiumExpiresIn: 0,
    userName: user.userName,
    platform: "lane-ios",
    avatarUrl: user.avatarUrl,
    headerUrl: user.headerUrl,
    laneId: user.laneId,
    statusTrack: null,
    statusTrackId: null,
    publicPlaylists: Object.values(db.playlists).filter(p => p.creatorLid === user.laneId && p.visibility !== "private"),
    followersCount: followers,
    followingCount: following,
    isFollowing: viewerLaneId ? (db.follows[viewerLaneId] || []).includes(user.laneId) : false,
    equippedBadgeId: null,
    statusText: user.statusText
  };
}

app.get("/account", authMiddleware, (req, res) => {
  const u = req.user;
  res.json({
    telegramId: u.telegramId,
    displayedName: u.displayedName,
    userName: u.userName,
    laneId: u.laneId,
    email: null,
    premiumExpiresIn: 0,
    avatarUrl: u.avatarUrl,
    headerUrl: u.headerUrl,
    userPlaylists: Object.values(db.playlists).filter(p => p.creatorLid === u.laneId).map(p => p.playlistId),
    deviceIds: [],
    searchHistory: [],
    equippedBadgeId: null,
    countryCode: u.countryCode || "",
    isAutoRenewalActive: false,
    statusText: u.statusText
  });
});

app.get("/user-info", authMiddleware, (req, res) => {
  const user = db.users[String(req.query.laneId || "")];
  if (!user) return res.status(404).json({ code: "NOT_FOUND", message: "User not found" });
  res.json(publicUser(user, req.user.laneId));
});

app.post("/user/edit", authMiddleware, (req, res) => {
  const u = req.user;
  u.displayedName = String(req.body?.name ?? u.displayedName);
  u.userName = String(req.body?.username ?? u.userName);
  u.avatarUrl = String(req.body?.avatarUrl ?? u.avatarUrl);
  u.headerUrl = String(req.body?.headerUrl ?? u.headerUrl);
  u.statusText = String(req.body?.statusText ?? u.statusText);
  u.updatedAt = Date.now();
  saveDB();
  res.json({ ok: true, user: publicUser(u, u.laneId) });
});

app.get("/user/check-user-name", authMiddleware, (req, res) => {
  const username = String(req.query.username || "").toLowerCase();
  const exists = Object.values(db.users).some(u => u.userName?.toLowerCase() === username && u.laneId !== req.user.laneId);
  res.json({ available: !exists });
});

function durationText(ms) {
  const total = Math.max(0, Math.floor(Number(ms || 0) / 1000));
  const m = Math.floor(total / 60);
  const s = String(total % 60).padStart(2, "0");
  return m + ":" + s;
}

function mapItunesTrack(x) {
  return {
    songId: "apple:" + x.trackId,
    platform: "apple",
    title: x.trackName || x.collectionName || "Unknown track",
    artistsDisplayedName: x.artistName || "Unknown artist",
    coverUrl: String(x.artworkUrl100 || "").replace("100x100bb", "600x600bb"),
    duration: durationText(x.trackTimeMillis),
    genre: x.primaryGenreName || "",
    artistAvatars: []
  };
}

async function itunesSearch(term, limit = 30) {
  const url = new URL("https://itunes.apple.com/search");
  url.searchParams.set("term", term);
  url.searchParams.set("entity", "song");
  url.searchParams.set("limit", String(Math.min(Math.max(limit, 1), 100)));
  const response = await fetch(url, { headers: { "User-Agent": "Lane-iOS-Backend/1.0" } });
  if (!response.ok) throw new Error("iTunes search HTTP " + response.status);
  const json = await response.json();
  return (json.results || []).map(x => ({ raw: x, track: mapItunesTrack(x) }));
}

async function itunesLookup(trackId) {
  const numeric = String(trackId || "").replace(/^apple:/, "");
  const url = new URL("https://itunes.apple.com/lookup");
  url.searchParams.set("id", numeric);
  const response = await fetch(url, { headers: { "User-Agent": "Lane-iOS-Backend/1.0" } });
  if (!response.ok) throw new Error("iTunes lookup HTTP " + response.status);
  const json = await response.json();
  return json.results?.[0] || null;
}

app.get("/platforms/search", authMiddleware, async (req, res) => {
  try {
    const q = String(req.query.q || "").trim();
    if (!q) return res.json({ results: [], searchToken: null });
    const results = await itunesSearch(q, 50);
    res.json({
      results: results.map(({ track }) => ({
        type: "track",
        track,
        artist: null,
        platform: "apple",
        album: null,
        playlist: null
      })),
      searchToken: crypto.randomUUID()
    });
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

app.get("/platforms/v2/hints", authMiddleware, async (req, res) => {
  try {
    const q = String(req.query.q || "").trim();
    const results = q ? await itunesSearch(q, 8) : [];
    res.json(results.map(({ track }) => track.title));
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

function pushRecent(userId, track) {
  const list = db.recent[userId] || [];
  const key = track.songId;
  db.recent[userId] = [track, ...list.filter(t => t.songId !== key)].slice(0, 100);
  saveDB();
}

app.get("/track/stream", authMiddleware, async (req, res) => {
  try {
    const item = await itunesLookup(req.query.trackId);
    if (!item?.previewUrl) return res.status(404).json({ code: "NO_STREAM", message: "Preview stream is unavailable" });
    const track = mapItunesTrack(item);
    pushRecent(req.user.laneId, track);
    res.json({
      url: item.previewUrl,
      trackId: track.songId,
      playbackToken: crypto.randomUUID(),
      ttl: 3600
    });
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

app.get("/track/download", authMiddleware, async (req, res) => {
  try {
    const item = await itunesLookup(req.query.trackId);
    if (!item?.previewUrl) return res.status(404).json({ code: "NO_DOWNLOAD", message: "Preview download is unavailable" });
    res.json({
      url: item.previewUrl,
      trackId: "apple:" + item.trackId,
      playbackToken: crypto.randomUUID(),
      ttl: 3600
    });
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

app.get("/feed/home", authMiddleware, async (req, res) => {
  try {
    const recent = db.recent[req.user.laneId] || [];
    const discovery = await itunesSearch(recent[0]?.artistsDisplayedName || "top hits", 20);
    res.json({
      recent,
      tracks: discovery.map(x => x.track),
      playlists: Object.values(db.playlists).filter(p => p.creatorLid === req.user.laneId)
    });
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

app.get("/user/recent", authMiddleware, (req, res) => {
  res.json(db.recent[req.user.laneId] || []);
});

app.get("/user/albums", authMiddleware, (_req, res) => res.json([]));
app.get("/user/artists", authMiddleware, (_req, res) => res.json([]));

function playlistForResponse(p) {
  const tracks = (p.playlistTracksIds || []).map(id => {
    for (const userTracks of Object.values(db.recent)) {
      const found = (userTracks || []).find(t => t.songId === id);
      if (found) return found;
    }
    return null;
  }).filter(Boolean);

  return {
    ...p,
    playlistTracks: tracks,
    tracksCount: p.playlistTracksIds?.length || 0,
    collaboratorIds: p.collaboratorIds || []
  };
}

app.get("/user/playlists", authMiddleware, (req, res) => {
  res.json(Object.values(db.playlists).filter(p => p.creatorLid === req.user.laneId).map(playlistForResponse));
});

app.post("/create-playlist", authMiddleware, (req, res) => {
  const playlistId = crypto.randomUUID();
  const p = {
    playlistId,
    playlistImageUrl: String(req.body?.playlistImageUrl || ""),
    playlistName: String(req.body?.playlistName || "Playlist"),
    playlistDescription: String(req.body?.playlistDescription || ""),
    playlistTracksIds: Array.isArray(req.body?.playlistTracks) ? req.body.playlistTracks : [],
    creatorLid: req.user.laneId,
    platform: "lane-ios",
    visibility: "public",
    collaboratorIds: []
  };
  db.playlists[playlistId] = p;
  saveDB();
  res.json(playlistForResponse(p));
});

app.post("/edit-playlist", authMiddleware, (req, res) => {
  const p = db.playlists[String(req.body?.playlistId || "")];
  if (!p || p.creatorLid !== req.user.laneId) return res.status(404).json({ code: "NOT_FOUND" });
  p.playlistImageUrl = String(req.body?.playlistImageUrl ?? p.playlistImageUrl);
  p.playlistName = String(req.body?.playlistName ?? p.playlistName);
  p.playlistDescription = String(req.body?.playlistDescription ?? p.playlistDescription);
  saveDB();
  res.json(playlistForResponse(p));
});

app.get("/delete-playlist", authMiddleware, (req, res) => {
  const id = String(req.query.playlistId || "");
  const p = db.playlists[id];
  if (!p || p.creatorLid !== req.user.laneId) return res.status(404).json({ code: "NOT_FOUND" });
  delete db.playlists[id];
  saveDB();
  res.json({ ok: true });
});

app.get("/playlist/:id", authMiddleware, (req, res) => {
  const p = db.playlists[req.params.id];
  if (!p) return res.status(404).json({ code: "NOT_FOUND" });
  res.json(playlistForResponse(p));
});

app.get("/playlist/:id/tracks", authMiddleware, (req, res) => {
  const p = db.playlists[req.params.id];
  if (!p) return res.status(404).json({ code: "NOT_FOUND" });
  const items = playlistForResponse(p).playlistTracks || [];
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.get("/user/playlist/add", authMiddleware, (req, res) => {
  const p = db.playlists[String(req.query.playlistId || "")];
  if (!p) return res.status(404).json({ code: "NOT_FOUND" });
  res.json({ ok: true, playlist: playlistForResponse(p) });
});

app.post("/user/playlist/add-tracks", authMiddleware, (req, res) => {
  const p = db.playlists[String(req.query.playlistId || "")];
  if (!p || p.creatorLid !== req.user.laneId) return res.status(404).json({ code: "NOT_FOUND" });
  const ids = Array.isArray(req.body) ? req.body.map(String) : [];
  p.playlistTracksIds = Array.from(new Set([...(p.playlistTracksIds || []), ...ids]));
  saveDB();
  res.json(playlistForResponse(p));
});

app.get("/user/playlist/remove-track", authMiddleware, (req, res) => {
  const p = db.playlists[String(req.query.playlistId || "")];
  if (!p || p.creatorLid !== req.user.laneId) return res.status(404).json({ code: "NOT_FOUND" });
  const trackId = String(req.query.trackId || "");
  p.playlistTracksIds = (p.playlistTracksIds || []).filter(id => id !== trackId);
  saveDB();
  res.json(playlistForResponse(p));
});

app.get("/users/search", authMiddleware, (req, res) => {
  const q = String(req.query.q || "").toLowerCase();
  res.json(Object.values(db.users)
    .filter(u => u.laneId !== req.user.laneId)
    .filter(u => !q || u.displayedName.toLowerCase().includes(q) || u.userName.toLowerCase().includes(q))
    .slice(0, 50)
    .map(u => publicUser(u, req.user.laneId)));
});

app.get("/user/friends", authMiddleware, (req, res) => {
  const ids = db.follows[req.user.laneId] || [];
  const items = ids.map(id => db.users[id]).filter(Boolean).map(u => publicUser(u, req.user.laneId));
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.post("/user/follow/:id", authMiddleware, (req, res) => {
  if (!db.users[req.params.id]) return res.status(404).json({ code: "NOT_FOUND" });
  const list = new Set(db.follows[req.user.laneId] || []);
  list.add(req.params.id);
  db.follows[req.user.laneId] = [...list];
  saveDB();
  res.json({ ok: true });
});

app.delete("/user/unfollow/:id", authMiddleware, (req, res) => {
  db.follows[req.user.laneId] = (db.follows[req.user.laneId] || []).filter(id => id !== req.params.id);
  saveDB();
  res.json({ ok: true });
});

app.get("/user/followers", authMiddleware, (req, res) => {
  const target = String(req.query.laneId || "");
  const items = Object.entries(db.follows)
    .filter(([, ids]) => (ids || []).includes(target))
    .map(([id]) => db.users[id])
    .filter(Boolean)
    .map(u => publicUser(u, req.user.laneId));
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.get("/user/following", authMiddleware, (req, res) => {
  const target = String(req.query.laneId || "");
  const items = (db.follows[target] || []).map(id => db.users[id]).filter(Boolean).map(u => publicUser(u, req.user.laneId));
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.get("/user/friends/presence", authMiddleware, (_req, res) => res.json([]));

function commentsFor(trackId) {
  return db.comments[trackId] || [];
}

app.get("/track/:trackId/comments", authMiddleware, (req, res) => {
  const items = commentsFor(req.params.trackId);
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.post("/comment/track", authMiddleware, (req, res) => {
  const trackId = String(req.body?.trackId || "");
  const text = String(req.body?.text || "").trim();
  if (!trackId || !text) return res.status(400).json({ code: "INVALID_COMMENT" });

  const comment = {
    id: crypto.randomUUID(),
    userName: req.user.userName || req.user.displayedName,
    userAvatar: req.user.avatarUrl,
    userId: req.user.laneId,
    text,
    likesCount: 0,
    repliesCount: 0,
    isLiked: false,
    attachment: String(req.body?.attachment || ""),
    timestamp: Date.now(),
    parentId: null,
    userEquippedBadgeImageUrl: null,
    replyToUserId: null,
    replyToUserName: null,
    likedBy: []
  };
  db.comments[trackId] = [comment, ...(db.comments[trackId] || [])];
  saveDB();
  res.json(comment);
});

function findComment(commentId) {
  for (const [trackId, list] of Object.entries(db.comments)) {
    const item = (list || []).find(c => c.id === commentId);
    if (item) return { trackId, item };
  }
  return null;
}

app.post("/comment/:id/like", authMiddleware, (req, res) => {
  const found = findComment(req.params.id);
  if (!found) return res.status(404).json({ code: "NOT_FOUND" });
  found.item.likedBy = Array.from(new Set([...(found.item.likedBy || []), req.user.laneId]));
  found.item.likesCount = found.item.likedBy.length;
  saveDB();
  res.json({ ok: true });
});

app.delete("/comment/:id/like", authMiddleware, (req, res) => {
  const found = findComment(req.params.id);
  if (!found) return res.status(404).json({ code: "NOT_FOUND" });
  found.item.likedBy = (found.item.likedBy || []).filter(id => id !== req.user.laneId);
  found.item.likesCount = found.item.likedBy.length;
  saveDB();
  res.json({ ok: true });
});

app.get("/comment/:id/replies", authMiddleware, (req, res) => {
  const items = Object.values(db.comments).flat().filter(c => c.parentId === req.params.id);
  res.json({ items, totalItems: items.length, page: 0, pageSize: items.length, totalPages: 1 });
});

app.post("/comment/:id/reply", authMiddleware, (req, res) => {
  const parent = findComment(req.params.id);
  if (!parent) return res.status(404).json({ code: "NOT_FOUND" });
  const reply = {
    id: crypto.randomUUID(),
    userName: req.user.userName || req.user.displayedName,
    userAvatar: req.user.avatarUrl,
    userId: req.user.laneId,
    text: String(req.body?.text || ""),
    likesCount: 0,
    repliesCount: 0,
    isLiked: false,
    attachment: String(req.body?.attachment || ""),
    timestamp: Date.now(),
    parentId: req.params.id,
    userEquippedBadgeImageUrl: null,
    replyToUserId: String(req.body?.replyToUserId || ""),
    replyToUserName: null,
    likedBy: []
  };
  db.comments[parent.trackId] = [...(db.comments[parent.trackId] || []), reply];
  parent.item.repliesCount = Number(parent.item.repliesCount || 0) + 1;
  saveDB();
  res.json(reply);
});

app.get("/track/stats", authMiddleware, (req, res) => {
  const comments = commentsFor(String(req.query.trackId || ""));
  res.json({ likesCount: 0, commentsCount: comments.length });
});

app.get("/track/:trackId/lyrics", authMiddleware, (_req, res) => {
  res.json({ lyrics: "", message: "Lyrics provider is not configured on this backend." });
});

app.get("/platforms/recommendations", authMiddleware, async (req, res) => {
  try {
    const item = await itunesLookup(req.query.trackId);
    const term = item?.artistName || item?.primaryGenreName || "top hits";
    const found = await itunesSearch(term, 20);
    res.json(found.map(x => x.track));
  } catch (error) {
    res.status(502).json({ code: "MUSIC_PROVIDER_ERROR", message: error.message });
  }
});

app.get("/platforms/album", authMiddleware, (_req, res) => res.json({}));
app.get("/platforms/artist", authMiddleware, (_req, res) => res.json({}));

app.get("/notifications", authMiddleware, (req, res) => {
  res.json(db.notifications[req.user.laneId] || []);
});
app.get("/notifications/unread-count", authMiddleware, (req, res) => {
  const items = db.notifications[req.user.laneId] || [];
  res.json({ count: items.filter(n => !n.read).length });
});
app.post("/notifications/:id/read", authMiddleware, (req, res) => {
  const items = db.notifications[req.user.laneId] || [];
  const item = items.find(n => n.id === req.params.id);
  if (item) item.read = true;
  saveDB();
  res.json({ ok: true });
});
app.post("/notifications/read-all", authMiddleware, (req, res) => {
  for (const item of db.notifications[req.user.laneId] || []) item.read = true;
  saveDB();
  res.json({ ok: true });
});

app.get("/user/search/history", authMiddleware, (_req, res) => res.json([]));
app.get("/import/telegram/start", authMiddleware, (_req, res) => res.json({ status: "ready", message: "Telegram import adapter is not configured yet." }));
app.get("/import/telegram/finish", authMiddleware, (_req, res) => res.json({ status: "finished" }));

app.use((req, res) => {
  res.status(404).json({ code: "NOT_FOUND", path: req.path });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log("Lane iOS backend listening on port", PORT);
  setupTelegramWebhook();
});
