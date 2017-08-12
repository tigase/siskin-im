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
    state INTEGER,
    preview TEXT
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
    timestamp INTEGER
);

CREATE INDEX IF NOT EXISTS vcards_cache_jid_idx on vcards_cache (
    jid
);

CREATE TABLE IF NOT EXISTS caps_features (
    node TEXT NOT NULL,
    feature TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS caps_features_node_idx on caps_features (
    node
);

CREATE INDEX IF NOT EXISTS caps_features_feature_idx on caps_features (
    feature
);

CREATE TABLE IF NOT EXISTS caps_identities (
    node TEXT NOT NULL,
    name TEXT,
    type TEXT,
    category TEXT
);

CREATE INDEX IF NOT EXISTS caps_indentities_node_idx on caps_identities (
    node
);

CREATE TABLE IF NOT EXISTS avatars_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL,
    account TEXT NOT NULL,
    hash TEXT NOT NULL,
    type TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS avatars_cache_jid_idx on avatars_cache (
    jid
);
