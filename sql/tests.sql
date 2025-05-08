-- ======================================
-- Check for Implementation
-- ======================================

-- Check Tables
SELECT * FROM Passenger;
SELECT * FROM MykiCard;
SELECT * FROM MykiPass;
SELECT * FROM Station;
SELECT * FROM Vehicle;
SELECT * FROM Scanner;
SELECT * FROM MykiTransaction;
SELECT * FROM Journey;
SELECT * FROM TouchEvent;

-- Check Partition (on TouchEvent)
SELECT DISTINCT t.name
FROM sys.partitions p
JOIN sys.tables t ON p.object_id = t.object_id
WHERE p.partition_number <> 1;

SELECT partition_number, row_count
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID('Journey');

-- Check Indexs

-- This helps check if the card has an active Myki Pass
-- Used in: status = 'Active' AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
EXEC sp_helpindex 'MykiPass';

-- This helps find the most recent TouchOn of a card
-- Used in: WHERE card_no = ? AND event_type = 'TouchOn' ORDER BY event_time DESC
EXEC sp_helpindex 'TouchEvent';

-- This helps check if a journey was finished (touch off or not)
-- Used in: WHERE txn_no = ? AND is_complete = 0
EXEC sp_helpindex 'Journey';

-- This helps check balance and expiry faster
-- Used to check if a card is valid and has enough money
EXEC sp_helpindex 'MyKiCard';


-- ======================================
-- Task 3: Test for touchOn()
-- ======================================

-- Drop Procedure
DROP PROCEDURE IF EXISTS touchOn;

-- This card is expired → should fail
EXEC touchOn @card_no = 201, @scanner_id = 501;

-- Has valid Myki Pass → should succeed
EXEC touchOn @card_no = 202, @scanner_id = 501;

-- Has money, not touched in 2 hours → should charge fare
EXEC touchOn @card_no = 203, @scanner_id = 501;

-- Has money, touched within 2 hours → should not charge fare, but record a new transaction
EXEC touchOn @card_no = 204, @scanner_id = 501;

-- No pass and no money → should fail
EXEC touchOn @card_no = 205, @scanner_id = 501;
