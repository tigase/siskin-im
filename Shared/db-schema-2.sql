ALTER TABLE chats RENAME TO chats_old;

CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    type INTEGER NOT NULL,
    timestamp INTEGER,
    thread_id TEXT,
    resource TEXT,
    nickname TEXT,
    password TEXT,
    room_state INTEGER
);

INSERT INTO chats (
    account, jid, type, timestamp, thread_id, resource, nickname, password, room_state
)
SELECT account, jid, type, timestamp, thread_id, resource, nickname, password, room_state
FROM chats_old;

DROP TABLE chats_old;

CREATE INDEX IF NOT EXISTS chat_jid_idx on chats (
    jid, account
);

ALTER TABLE chat_history RENAME TO chat_history_old;

CREATE TABLE IF NOT EXISTS chat_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    author_jid TEXT COLLATE NOCASE,
    author_nickname TEXT,
    timestamp INTEGER,
    item_type INTEGER,
    data TEXT,
    stanza_id TEXT,
    state INTEGER,
    preview TEXT,
    error TEXT
);

INSERT INTO chat_history (
    account, jid, author_jid, author_nickname, timestamp, item_type, data, stanza_id, state, preview
)
SELECT account, jid, author_jid, author_nickname, timestamp, item_type, data, stanza_id, state, preview
FROM chat_history_old;

DROP TABLE chat_history_old;

CREATE INDEX IF NOT EXISTS chat_history_account_jid_timestamp_idx on chat_history (
    account, jid, timestamp
);

CREATE INDEX IF NOT EXISTS chat_history_account_jid_state_idx on chat_history (
    account, jid, state
);

ALTER TABLE roster_items RENAME TO roster_items_old;
ALTER TABLE roster_items_groups RENAME TO roster_items_groups_old;

CREATE TABLE IF NOT EXISTS roster_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    name TEXT,
    subscription TEXT,
    timestamp INTEGER,
    ask INTEGER
);

INSERT INTO roster_items (
    account, jid, name, subscription, timestamp, ask
)
SELECT account, jid, name, subscription, timestamp, ask
FROM roster_items_old;

CREATE TABLE IF NOT EXISTS roster_items_groups (
    item_id INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    FOREIGN KEY(item_id) REFERENCES roster_items(id),
    FOREIGN KEY(group_id) REFERENCES roster_groups(id)
);

INSERT INTO roster_items_groups (
    item_id, group_id
)
SELECT i.id, go.group_id
FROM
    roster_items_groups_old go
    INNER JOIN roster_items_old io on io.id = go.item_id
    INNER JOIN roster_items i on i.jid = io.jid;

DROP TABLE roster_items_groups_old;
DROP TABLE roster_items_old;

CREATE INDEX IF NOT EXISTS roster_item_jid_idx on roster_items (
    jid, account
);

CREATE INDEX IF NOT EXISTS roster_item_groups_item_id_idx ON roster_items_groups (item_id);
CREATE INDEX IF NOT EXISTS roster_item_groups_group_id_idx ON roster_items_groups (group_id);

ALTER TABLE vcards_cache RENAME TO vcards_cache_old;

CREATE TABLE IF NOT EXISTS vcards_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL COLLATE NOCASE,
    data TEXT,
    timestamp INTEGER
);

INSERT INTO vcards_cache (
    jid, data, timestamp
)
SELECT jid, data, timestamp
FROM vcards_cache_old;

DROP TABLE vcards_cache_old;

CREATE INDEX IF NOT EXISTS vcards_cache_jid_idx on vcards_cache (
    jid
);

ALTER TABLE avatars_cache RENAME TO avatars_cache_old;

CREATE TABLE IF NOT EXISTS avatars_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL COLLATE NOCASE,
    account TEXT NOT NULL COLLATE NOCASE,
    hash TEXT NOT NULL,
    type TEXT NOT NULL
);

INSERT INTO avatars_cache (
    jid, account, hash, type
)
SELECT jid, account, hash, type
FROM avatars_cache_old;

DROP TABLE avatars_cache_old;

CREATE INDEX IF NOT EXISTS avatars_cache_jid_idx on avatars_cache (
    jid
);
