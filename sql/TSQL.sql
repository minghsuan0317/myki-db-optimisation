CREATE OR ALTER PROCEDURE touchOn 
  @card_no INT,
  @scanner_id INT, 
  @event_time DATETIME = NULL -- the time when you touch on
AS
BEGIN
    IF @event_time IS NULL
        SET @event_time = GETDATE();
    DECLARE @station_id INT;
    -- =========================================
    -- Step 1：Check if the your myki card is expired
    -- =========================================
    BEGIN TRY
        DECLARE @expiry_date DATE; 

        SELECT @expiry_date = expiry_date
        FROM MyKiCard
        WHERE card_no = @card_no;

        -- If the card is not found (no expiry date), touch on fails
        IF @expiry_date IS NULL
        BEGIN
            PRINT '[Touch on failed] card is not found';
            RETURN;
        END

        -- If the card is already expired, touch on fails
        IF @expiry_date < CAST(@event_time AS DATE) -- Use CAST to get date only
        BEGIN
            PRINT '[Touch on failed] card expired';
            RETURN;         
        END
    END TRY
    BEGIN CATCH
    PRINT '[Error - step 1] ' + ERROR_MESSAGE();
    RETURN;
    END CATCH
    -- =========================================
    -- Step 2：Check if this new touch on is within 2 hours of the previous touch on.
    -- =========================================
    BEGIN TRY
        DECLARE @last_touch_time DATETIME;

        SELECT TOP 1 @last_touch_time = event_time -- get the most recent touch on time
        FROM TouchEvent
        WHERE card_no = @card_no AND event_type = 'TouchOn'
        ORDER BY event_time DESC;  

        -- If there is a new touch on and within 120 minutes (2hrs) 
        -- >> touchOn success, and add to the log but no need to charged
        IF @last_touch_time IS NOT NULL AND DATEDIFF(MINUTE, @last_touch_time, @event_time) <= 120
        BEGIN
            -- Within 2 hours: record new transaction, but no fare is charged
            INSERT INTO MykiTransaction (
                txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
            ) VALUES (
                'TouchOn', @event_time, 'Success', 'NoCharge', 0.00, @card_no, @scanner_id
            );

            -- Get the transaction ID for inserting TouchEvent
            -- Use SCOPE_IDENTITY() to get ID of the row you just added into the table
            DECLARE @txn_no_repeat INT = SCOPE_IDENTITY();

            -- Get the station ID from the scanner      
            SELECT @station_id = station_id FROM Scanner WHERE scanner_id = @scanner_id;
            
            -- Add a new journey record for this Touch On
            INSERT INTO Journey (txn_no, touch_on_time, touch_on_station_id, fare_charged, is_complete, fare_type)
            VALUES (@txn_no_repeat, @event_time, @station_id, 0.00, 0, 'NoCharge');

            -- Stored the journey ID for inserting
            DECLARE @jid_repeat INT = SCOPE_IDENTITY();

            -- Add a record to TouchEvent as well (since touch on succeeded)
            INSERT INTO TouchEvent (
                event_time, event_type, event_status, fare_charged,
                card_no, scanner_id, journey_id, txn_no
            ) VALUES (
                @event_time, 'TouchOn', 'Success', 0.00, @card_no, @scanner_id, @jid_repeat, @txn_no_repeat
            ); 

            PRINT '[Touch on success] no additional fare (within 2 hours)';
            RETURN;
        END
    END TRY
    BEGIN CATCH
        PRINT '[Error - Step 2] ' + ERROR_MESSAGE();
        RETURN;
    END CATCH
    -- =========================================
    -- Step 3：If the ticket has journey not yet finished (haven't touch off)
    -- =========================================
    BEGIN TRY
        DECLARE @has_pass INT; -- Whether the card has a valid pass
        DECLARE @unclosed_count INT;
        DECLARE @balance DECIMAL(6,2);
        DECLARE @fare DECIMAL(6,2) = 5.50; -- Defalt Fare (zone 1 + 2)

        -- Count how many unfinished journeys
        SELECT @unclosed_count = COUNT(*)
        FROM Journey
        WHERE txn_no IN (
            SELECT txn_no FROM MykiTransaction WHERE card_no = @card_no
        ) AND is_complete = 0;  -- 0 means not touch off yet

        -- Unfinished journey exists
        IF @unclosed_count > 0
        BEGIN
            -- Step 3.1：Check if there is a valid Myki Pass (Active + current date in range)
            SELECT @has_pass = COUNT(*) -- Count how many linked pass 
            FROM MykiPass
            WHERE card_no = @card_no
            AND status = 'Active'
            AND start_date <= @event_time
            AND end_date >= @event_time;  -- Check if current time is within pass's valid period

            IF @has_pass > 0
            BEGIN
                -- Use Myki Pass: no fare charged, just log transaction and event
                INSERT INTO MykiTransaction (
                    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
                ) VALUES (
                    'TouchOn', @event_time, 'Success', 'MykiPass', 0.00, @card_no, @scanner_id
                );

                -- Stored the transaction ID for inserting
                DECLARE @txn_no_pass INT = SCOPE_IDENTITY(); 

                -- Get the station ID from the scanner      
                SELECT @station_id = station_id FROM Scanner WHERE scanner_id = @scanner_id;

                -- Add a new journey record for this Touch On
                INSERT INTO Journey (txn_no, touch_on_time, touch_on_station_id, fare_charged, is_complete, fare_type)
                VALUES (@txn_no_pass, @event_time, @station_id, 0.00, 0, 'MykiPass');

                -- Stored the journey ID for inserting
                DECLARE @jid_pass INT = SCOPE_IDENTITY();

                -- Add one record in TouchEvent as well (because touch on success)
                INSERT INTO TouchEvent (
                    event_time, event_type, event_status, fare_charged,
                    card_no, scanner_id, journey_id, txn_no
                ) VALUES (
                    @event_time, 'TouchOn', 'Success', 0.00, @card_no, @scanner_id, @jid_pass, @txn_no_pass
                );

                PRINT '[Touch on success] using Myki Pass';
                RETURN;
            END
            ELSE
            BEGIN
                -- Step 3.2：No valid pass, use Myki Money and charge fare
                SELECT @balance = myki_money_balance 
                FROM MyKiCard
                WHERE card_no = @card_no;

                 -- Check balance of the card
                IF @balance < @fare                

                BEGIN
                    PRINT '[Touch on failed] unfinished trip and insufficient balance'; 
                    RETURN;
                END

                -- Enough balance: charge $5.50 using Myki Money
                -- Add a record in MykiTransaction with a charged amount of 5.50
                INSERT INTO MykiTransaction (
                    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
                ) VALUES (
                    'TouchOn', @event_time, 'Success', 'MykiMoney', @fare, @card_no, @scanner_id
                ); 
                
                DECLARE @txn_no_money INT = SCOPE_IDENTITY();  

                -- Get the station ID from the scanner      
                SELECT @station_id = station_id FROM Scanner WHERE scanner_id = @scanner_id;

                -- Add a new journey record for this Touch On
                INSERT INTO Journey (txn_no, touch_on_time, touch_on_station_id, fare_charged, is_complete, fare_type)
                VALUES (@txn_no_money, @event_time, @station_id, @fare, 0, 'MykiMoney');

                -- Stored the journey ID for inserting
                DECLARE @jid_money INT = SCOPE_IDENTITY();

                INSERT INTO TouchEvent (
                    event_time, event_type, event_status, fare_charged,
                    card_no, scanner_id, journey_id, txn_no
                ) VALUES (
                    @event_time, 'TouchOn', 'Success', @fare, @card_no, @scanner_id, @jid_money, @txn_no_money
                ); 

                -- Update myki card balance (old card balance - fare)
                UPDATE MyKiCard
                SET myki_money_balance = myki_money_balance - @fare
                WHERE card_no = @card_no;
                PRINT '[Touch on success] using Myki Money';
                RETURN;
            END
        END
    -- =========================================
    -- Step 4：If the card doesn't have an uncompleted journey
    -- =========================================        
        ELSE
        BEGIN
            -- Check if there is a valid pass first
            SELECT @has_pass = COUNT(*)
            FROM MykiPass
            WHERE card_no = @card_no
            AND status = 'Active'
            AND start_date <= @event_time
            AND end_date >= @event_time;

            -- If there is, use pass and log in transaction and TouchEvent    
            IF @has_pass > 0
            BEGIN
                INSERT INTO MykiTransaction (
                    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
                ) VALUES (
                    'TouchOn', @event_time, 'Success', 'MykiPass', 0.00, @card_no, @scanner_id
                );

                DECLARE @txn_no_new_pass INT = SCOPE_IDENTITY();

                -- Get the station ID from the scanner      
                SELECT @station_id = station_id FROM Scanner WHERE scanner_id = @scanner_id;
                
                -- Add a new journey record for this Touch On
                INSERT INTO Journey (txn_no, touch_on_time, touch_on_station_id, fare_charged, is_complete, fare_type)
                VALUES (@txn_no_new_pass, @event_time, @station_id, 0.00, 0, 'MykiPass');

                -- Stored the journey ID for inserting
                DECLARE @jid_new_pass INT = SCOPE_IDENTITY();

                INSERT INTO TouchEvent (
                    event_time, event_type, event_status, fare_charged,
                    card_no, scanner_id, journey_id, txn_no
                ) VALUES (
                    @event_time, 'TouchOn', 'Success', 0.00, @card_no, @scanner_id, @jid_new_pass, @txn_no_new_pass
                );

                PRINT '[Touch on success] using Myki Pass (no unfinished journey)';
                RETURN;
            END
            ELSE
            -- If not, check if there has enough money in Myki Money  
            BEGIN
                SELECT @balance = myki_money_balance
                FROM MyKiCard
                WHERE card_no = @card_no;

                -- if the balance is insufficient, touch on fails
                IF @balance < @fare
                BEGIN
                    PRINT '[Touch on failed] no pass and insufficient balance';
                    RETURN;
                END

                -- if the balance is enough, use Myki Money to pay the fare
                INSERT INTO MykiTransaction (
                    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
                ) VALUES (
                    'TouchOn', @event_time, 'Success', 'MykiMoney', @fare, @card_no, @scanner_id
                );

                DECLARE @txn_no_new_money INT = SCOPE_IDENTITY();

                -- Get the station ID from the scanner      
                SELECT @station_id = station_id FROM Scanner WHERE scanner_id = @scanner_id;
                
                -- Add a new journey record for this Touch On
                INSERT INTO Journey (txn_no, touch_on_time, touch_on_station_id, fare_charged, is_complete, fare_type)
                VALUES (@txn_no_new_money, @event_time, @station_id, @fare, 0, 'MykiMoney');

                -- Stored the journey ID for inserting
                DECLARE @jid_new_money INT = SCOPE_IDENTITY();

                INSERT INTO TouchEvent (
                    event_time, event_type, event_status, fare_charged,
                    card_no, scanner_id, journey_id, txn_no
                ) VALUES (
                    @event_time, 'TouchOn', 'Success', @fare, @card_no, @scanner_id, @jid_new_money, @txn_no_new_money
                );

                UPDATE MyKiCard
                SET myki_money_balance = myki_money_balance - @fare
                WHERE card_no = @card_no;

                PRINT '[Touch on success] using Myki Money';
                RETURN;
            END
        END
    END TRY
    BEGIN CATCH
        PRINT '[Error - Step 3/4] ' + ERROR_MESSAGE();
        RETURN;
    END CATCH
END;


