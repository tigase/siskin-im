--
-- Tigase iOS Messenger Documentation - bootstrap configuration for all Tigase projects
-- Copyright (C) 2004 Tigase, Inc. (office@tigase.com) - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
--

ALTER TABLE roster_items ADD COLUMN annotations TEXT;

ALTER TABLE chat_history ADD COLUMN server_msg_id TEXT;
ALTER TABLE chat_history ADD COLUMN remote_msg_id TEXT;
ALTER TABLE chat_history ADD COLUMN participant_id TEXT;

CREATE INDEX IF NOT EXISTS chat_history_account_jid_server_msg_id_idx on chat_history (
    account, server_msg_id
);
