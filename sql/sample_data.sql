-- ======================================
-- Add sample data to run the tests
-- ======================================


-- Delete Data
DELETE FROM TouchEvent;
DELETE FROM Journey;
DELETE FROM MykiTransaction;
DELETE FROM MykiPass;
DELETE FROM MyKiCard;
DELETE FROM Passenger;
DELETE FROM Scanner;
DELETE FROM Station;
DELETE FROM Vehicle;

-- Add Passengers
INSERT INTO Passenger VALUES
(101, 'Ross Geller', '1990-01-01', 'expired@example.com', '0401000001', 'Melbourne VIC'),
(102, 'Rachel Green', '1990-02-01', 'pass@example.com', '0401000002', 'Melbourne VIC'),
(103, 'Monica Geller', '1990-03-01', 'money@example.com', '0401000003', 'Melbourne VIC'),
(104, 'Chandler Bing', '1990-04-01', '2hours@example.com', '0401000004', 'Melbourne VIC'),
(105, 'Joey Tribbiani', '1990-05-01', 'poor@example.com', '0401000005', 'Melbourne VIC');

-- Add Myki Cards
INSERT INTO MyKiCard (card_no, myki_money_balance, expiry_date, card_type, passenger_id) VALUES
(201, 5.0, '2024-12-31', 'Adult', 101),  -- Ticket 1: Expired
(202, 5.0, '2025-12-31', 'Adult', 102),  -- Ticket 2: Has Pass
(203, 20.0, '2025-12-31', 'Adult', 103), -- Ticket 3: Has Money, Not Live
(204, 20.0, '2025-12-31', 'Adult', 104), -- Ticket 4: Has Money, Live
(205, 0.0, '2025-12-31', 'Adult', 105);  -- Ticket 5: No Money


-- Add MykiPass
INSERT INTO MyKiPass (pass_id, pass_type, zone_coverage, start_date, end_date, status, card_no) VALUES
(301, '30-day', 'Zone 1+2', '2025-05-01', '2025-05-30', 'Active', 202);


-- Add Station
INSERT INTO Station VALUES
(401, 'Melbourne Central', 'Train'),
(402, 'Fliders', 'Train');


-- Add Vehicle
INSERT INTO Vehicle VALUES
(001, 'Tram 30', 'Tram'),
(002, 'Tram 96', 'Tram');


-- Add Scanner
INSERT INTO Scanner VALUES
(501, 'Platform', -37.8, 144.9, 'Zone 1', NULL, 401),
(502, 'Onboard', -37.5, 145.9, 'Zone 1', 002, NULL);


-- Add MykiTransaction, Journey and TouchEvent

-- Add a transaction for Ticket 3 to simulate "not live" state
INSERT INTO MykiTransaction (
    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
) VALUES (
    'TouchOn', '2025-05-01 11:00:00', 'Success', 'MykiMoney', 5.50, 203, 501);

DECLARE @txn_203 INT = SCOPE_IDENTITY();

INSERT INTO Journey (
    txn_no, touch_on_time, touch_on_station_id, touch_off_time, touch_off_station_id, fare_charged, is_complete, fare_type
) VALUES (
    @txn_203, '2025-05-01 11:00:00', 401, '2025-05-01 11:30:00', 402, 5.50, 1, 'MykiMoney'
);

DECLARE @journey_203 INT = SCOPE_IDENTITY();

INSERT INTO TouchEvent (
    event_time, event_type, event_status, fare_charged, card_no, scanner_id, journey_id, txn_no
) VALUES (
    '2025-05-01 11:00:00', 'TouchOn', 'Success', 5.50, 203, 501, @journey_203, @txn_203
);


-- Add a transaction for Ticket 4 to simulate "live" state (touch on within 2 hours)
INSERT INTO MykiTransaction (
    txn_type, txn_time, txn_status, payment_type, amount, card_no, scanner_id
) VALUES ('TouchOn', '2025-05-02 14:40:00', 'Success', 'MykiMoney', 5.50, 204, 501);

DECLARE @txn_204 INT = SCOPE_IDENTITY();

INSERT INTO Journey (
    txn_no, touch_on_time, touch_on_station_id, touch_off_time, touch_off_station_id, fare_charged, is_complete, fare_type
) VALUES (
    @txn_204, '2025-05-02 14:40:00', 401, '2025-05-02 14:50:00', 402, 5.50, 1, 'MykiMoney'
);

DECLARE @journey_204 INT = SCOPE_IDENTITY();

INSERT INTO TouchEvent (
    event_time, event_type, event_status, fare_charged, card_no, scanner_id, journey_id, txn_no
) VALUES (
    '2025-05-02 14:40:00', 'TouchOn', 'Success', 5.50, 204, 501, @journey_204, @txn_204
);
