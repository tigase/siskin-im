--
-- Tigase iOS Messenger Documentation - bootstrap configuration for all Tigase projects
-- Copyright (C) 2004 Tigase, Inc. (office@tigase.com) - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
--

UPDATE chat_history SET state = 11 WHERE state = 5;
UPDATE chat_history SET state = 5 WHERE state = 9;
UPDATE chat_history SET state = 9 WHERE state = 4;
UPDATE chat_history SET state = 4 WHERE state = 7;
UPDATE chat_history SET state = 7 WHERE state = 6;
UPDATE chat_history SET state = 6 WHERE state = 8;
