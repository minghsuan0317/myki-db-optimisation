-- ======================================
-- Clear all tables to avoid duplicate data
-- ======================================

-- First Drop Table
DROP TABLE IF EXISTS TouchEvent;
DROP TABLE IF EXISTS Journey;
DROP TABLE IF EXISTS MykiTransaction;
DROP PARTITION SCHEME ps_TouchEventRange;
DROP PARTITION FUNCTION pf_TouchEventRange;

-- Second Drop Table
DROP TABLE IF EXISTS MykiPass;
DROP TABLE IF EXISTS MyKiCard;

-- Third Drop Table
DROP TABLE IF EXISTS Passenger;
DROP TABLE IF EXISTS Scanner;
DROP TABLE IF EXISTS Station;
DROP TABLE IF EXISTS Vehicle;

-- ======================================
-- Create Tables
-- ======================================

CREATE TABLE Passenger (
  passenger_id INT PRIMARY KEY,
  passenger_name VARCHAR(100),
  dob DATE,
  email VARCHAR(100),
  phone_num VARCHAR(20),
  address VARCHAR(200)
);

CREATE TABLE MyKiCard (
  card_no INT PRIMARY KEY,
  myki_money_balance DECIMAL(6,2),
  expiry_date DATE,
  card_type VARCHAR(20),
  passenger_id INT,
  FOREIGN KEY (passenger_id) REFERENCES Passenger(passenger_id)
);

CREATE TABLE MykiPass (
  pass_id INT PRIMARY KEY,
  pass_type VARCHAR(20),
  zone_coverage VARCHAR(20),
  start_date DATE,
  end_date DATE,
  status VARCHAR(20),
  card_no INT,
  FOREIGN KEY (card_no) REFERENCES MyKiCard(card_no)
);

CREATE TABLE Station (
  station_id INT PRIMARY KEY,
  station_name VARCHAR(100),
  station_type VARCHAR(50)
);

CREATE TABLE Vehicle (
  vehicle_id INT PRIMARY KEY,
  vehicle_route_name VARCHAR(100),
  vehicle_type VARCHAR(50)
);

CREATE TABLE Scanner (
  scanner_id INT PRIMARY KEY,
  scanner_type VARCHAR(20),
  gps_latitude DECIMAL(9,6),
  gps_longitude DECIMAL(9,6),
  zone VARCHAR(10),
  vehicle_id INT,
  station_id INT,
  FOREIGN KEY (vehicle_id) REFERENCES Vehicle(vehicle_id),
  FOREIGN KEY (station_id) REFERENCES Station(station_id)
  );

CREATE TABLE MykiTransaction (
  txn_no INT IDENTITY(1000,1) PRIMARY KEY,
  txn_type VARCHAR(20),
  txn_time DATETIME,
  txn_status VARCHAR(20),
  payment_type VARCHAR(20),
  amount DECIMAL(6,2),
  card_no INT,
  scanner_id INT,
  FOREIGN KEY (card_no) REFERENCES MyKiCard(card_no),
  FOREIGN KEY (scanner_id) REFERENCES Scanner(scanner_id)
);


CREATE TABLE Journey (
  journey_id INT IDENTITY(3000,1) PRIMARY KEY,
  touch_on_time DATETIME,
  touch_on_station_id INT,
  touch_off_time DATETIME,
  touch_off_station_id INT,
  fare_charged DECIMAL(6,2),
  is_complete BIT,
  fare_type VARCHAR(20),
  txn_no INT,
  FOREIGN KEY (txn_no) REFERENCES MykiTransaction(txn_no),
  FOREIGN KEY (touch_on_station_id) REFERENCES Station(station_id),
  FOREIGN KEY (touch_off_station_id) REFERENCES Station(station_id)
);

-- =========================================
-- Create Partition
-- =========================================

CREATE PARTITION FUNCTION pf_TouchEventRange (DATETIME)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01',
    '2025-02-01',
    '2025-03-01',
    '2025-04-01'
);

CREATE PARTITION SCHEME ps_TouchEventRange
AS PARTITION pf_TouchEventRange
ALL TO ([PRIMARY]);

CREATE TABLE TouchEvent (
  event_id INT IDENTITY(2000,1),
  event_time DATETIME NOT NULL,
  event_type VARCHAR(20),
  event_status VARCHAR(20),
  fare_charged DECIMAL(6,2),
  card_no INT,
  scanner_id INT,
  journey_id INT,
  txn_no INT,
  PRIMARY KEY (event_time, event_id),
  FOREIGN KEY (card_no) REFERENCES MyKiCard(card_no),
  FOREIGN KEY (scanner_id) REFERENCES Scanner(scanner_id),
  FOREIGN KEY (journey_id) REFERENCES Journey(journey_id),
  FOREIGN KEY (txn_no) REFERENCES MykiTransaction(txn_no)
)
ON ps_TouchEventRange(event_time);


-- =========================================
-- Create Indexs
-- =========================================

-- This helps check if the card has an active Myki Pass
-- Used in: status = 'Active' AND start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
CREATE INDEX idx_pass_validity ON MykiPass(card_no, status, start_date, end_date);

-- This helps find the most recent TouchOn of a card
-- Used in: WHERE card_no = ? AND event_type = 'TouchOn' ORDER BY event_time DESC
CREATE INDEX idx_touch_recent ON TouchEvent(card_no, event_time, event_type);

-- This helps check if a journey was finished (touch off or not)
-- Used in: WHERE txn_no = ? AND is_complete = 0
CREATE INDEX idx_journey_txn ON Journey(txn_no, is_complete, touch_on_time);

-- This helps check balance and expiry faster
-- Used to check if a card is valid and has enough money
CREATE INDEX idx_card_balance_check ON MyKiCard(card_no);
