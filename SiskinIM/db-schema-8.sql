--
-- Tigase iOS Messenger Documentation - bootstrap configuration for all Tigase projects
-- Copyright (C) 2004 Tigase, Inc. (office@tigase.com) - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
--

CREATE TABLE IF NOT EXISTS chats_read (
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    timestamp INTEGER,

    UNIQUE (account, jid)
);
