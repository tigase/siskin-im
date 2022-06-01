CREATE TABLE IF NOT EXISTS chats_read (
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    timestamp INTEGER,

    UNIQUE (account, jid)
);
