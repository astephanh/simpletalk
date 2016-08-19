/*
 * enable_xp_cmdshell.sql
 * Copyright (C) 2016 Stephan Helas <stephan.helas@pp-nt.com>
 *
 * Distributed under terms of the MIT license.
 */


-- To allow advanced options to be changed.
EXEC sp_configure 'show advanced options', 1;
GO
-- To update the currently configured value for advanced options.
RECONFIGURE;
GO

EXEC sp_configure 'xp_cmdshell', 1;
GO

-- To update the currently configured value for this feature.
RECONFIGURE;
GO



-- vim:et sw=2 ts=2 expandtab:
