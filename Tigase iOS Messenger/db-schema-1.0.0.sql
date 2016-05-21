CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL,
    jid TEXT NOT NULL,
    type INTEGER NOT NULL,
    timestamp INTEGER,
    thread_id TEXT,
    resource TEXT,
    nickname TEXT,
    password TEXT,
    room_state INTEGER
);

CREATE TABLE IF NOT EXISTS chat_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL,
    jid TEXT NOT NULL,
    author_jid TEXT,
    author_nickname TEXT,
    timestamp INTEGER,
    item_type INTEGER,
    data TEXT,
    stanza_id TEXT,
    state INTEGER
);

CREATE INDEX IF NOT EXISTS chat_history_jid_idx on chats (
    jid, account
);

CREATE TABLE IF NOT EXISTS roster_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL,
    jid TEXT NOT NULL,
    name TEXT,
    subscription TEXT,
    timestamp INTEGER,
    ask INTEGER
);

CREATE TABLE IF NOT EXISTS roster_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT
);

CREATE TABLE IF NOT EXISTS roster_items_groups (
    item_id INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    FOREIGN KEY(item_id) REFERENCES roster_items(id),
    FOREIGN KEY(group_id) REFERENCES roster_groups(id)
);

CREATE TABLE IF NOT EXISTS vcards_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL,
    data TEXT,
    avatar BLOB,
    avatar_hash TEXT,
    timestamp INTEGER
);

CREATE INDEX IF NOT EXISTS vcards_cache_jid_idx on vcards_cache (
    jid
);