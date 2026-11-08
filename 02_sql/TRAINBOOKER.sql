

-- สร้างตาราง Lines สำหรับเก็บข้อมูลสายรถไฟ
CREATE TABLE Lines (
    LineID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    LineName VARCHAR(50) NOT NULL
);

-- สร้างตาราง Stations สำหรับเก็บข้อมูลสถานีรถไฟ
CREATE TABLE Stations (
    StationID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    StationName VARCHAR(100) NOT NULL,
    LineID INT NOT NULL,
    StationOrder INT NOT NULL,
    Locations VARCHAR(100),
    FOREIGN KEY (LineID) REFERENCES Lines(LineID)
);


-- สร้างตาราง Trains สำหรับเก็บข้อมูลขบวนรถไฟ
CREATE TABLE Trains (
    TrainID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TrainName VARCHAR(100) NOT NULL,
    TrainType VARCHAR(20),
    TotalSeats INT CHECK (TotalSeats > 0)
);

-- ===== USERS =====
CREATE TABLE Users (
    UserID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Username VARCHAR(50) UNIQUE NOT NULL,
    Password VARCHAR(50) NOT NULL,
    FullName VARCHAR(100),
	Email VARCHAR(100),
    Phone VARCHAR(15)
);

-- ===== SCHEDULES =====
CREATE TABLE Schedules (
    ScheduleID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TrainID INT NOT NULL,
    OriginStationID INT NOT NULL,
    DestinationStationID INT NOT NULL,
    DepartureTime TIMESTAMP NOT NULL,
    ArrivalTime TIMESTAMP NOT NULL,
    Price DECIMAL(10,2),
    FOREIGN KEY (TrainID) REFERENCES Trains(TrainID),
    FOREIGN KEY (OriginStationID) REFERENCES Stations(StationID),
    FOREIGN KEY (DestinationStationID) REFERENCES Stations(StationID)
);

-- ===== BOOKINGS =====
CREATE TABLE Bookings (
    BookingID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    UserID INT NOT NULL,
    ScheduleID INT NOT NULL,
    Status VARCHAR(50),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (ScheduleID) REFERENCES Schedules(ScheduleID)
);

-- ===== TICKETS =====
CREATE TABLE Tickets (
    TicketID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BookingID INT NOT NULL,
    SeatNumber VARCHAR(10),
    PassengerName VARCHAR(100),
    FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
);

-- ===== PAYMENTS =====
CREATE TABLE Payments (
    PaymentID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BookingID INT NOT NULL,
    Amount DECIMAL(10,2),
    PaymentMethod VARCHAR(50),
    PaymentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
);
-------------------------------


-- 1) Lines
INSERT INTO Lines (LineName) VALUES
('สายใต้'),
('สายเหนือ');



-- 2) Stations 
INSERT INTO Stations (StationName, LineID, StationOrder, Location) VALUES
('กรุงเทพอภิวัฒน์',1,1,'กรุงเทพมหานคร'),
('ตลิ่งชัน',1,2,'กรุงเทพมหานคร'),
('ศาลายา',1,3,'นครปฐม'),
('นครปฐม',1,4,'นครปฐม'),
('กรุงเทพอภิวัฒน์',2,1,'กรุงเทพมหานคร'),
('บางซื่อ',2,2,'กรุงเทพมหานคร'),
('ดอนเมือง',2,3,'กรุงเทพมหานคร'),
('หลักสี่',2,4,'กรุงเทพมหานคร'),
('เชียงราก',2,5,'ปทุมธานี'),
('ปทุมธานี',2,6,'ปทุมธานี');



-- 3) Users 
INSERT INTO Users (Username, Password, FullName, Email, Phone) VALUES
('user01','1234','Somchai','somchai@email.com','0811111111'),
('user02','1234','Anan','anan@email.com','0822222222'),
('user03','1234','Suda','suda@email.com','0833333333'),
('user04','1234','Wichai','wichai@email.com','0844444444'),
('user05','1234','Mana','mana@email.com','0855555555'),
('user06','1234','Jane','jane@email.com','0866666666');



-- 4) Trains
INSERT INTO Trains (TrainName, TrainType, TotalSeats) VALUES
('South Express','แอร์',500),
('North Local','พัดลม',350),
('North Express','แอร์',450),
('South Local','พัดลม',300),
('InterCity','แอร์',550),
('Rapid North','แอร์',420);



-- 5) Schedules (ขึ้นกับ Trains + Stations)
INSERT INTO Schedules
(TrainID, OriginStationID, DestinationStationID, DepartureTime, ArrivalTime, Price)
VALUES

-- สายใต้ ขาไป
(1,1,4,'2026-03-10 08:00','2026-03-10 09:30',120),
(4,1,4,'2026-03-10 08:45','2026-03-10 10:15',100),
(5,1,4,'2026-03-10 09:30','2026-03-10 11:00',150),

-- สายใต้ ขากลับ
(1,4,1,'2026-03-10 12:00','2026-03-10 13:30',120),
(4,4,1,'2026-03-10 12:45','2026-03-10 14:15',100),
(5,4,1,'2026-03-10 13:30','2026-03-10 15:00',150),

-- สายเหนือ ขาไป
(2,5,10,'2026-03-10 07:30','2026-03-10 08:40',80),
(3,5,7,'2026-03-10 15:30','2026-03-10 16:00',90),
(6,5,7,'2026-03-10 16:00','2026-03-10 16:30',110),	
(3,5,10,'2026-03-10 08:15','2026-03-10 09:25',140),
(6,5,10,'2026-03-10 09:00','2026-03-10 10:10',160),
(6,5,10,'2026-03-10 09:00','2026-03-10 10:10',160),
-- สายเหนือ ขากลับ
(2,10,5,'2026-03-10 11:30','2026-03-10 12:40',80),
(3,10,5,'2026-03-10 12:15','2026-03-10 13:25',140),
(6,10,5,'2026-03-10 13:00','2026-03-10 14:10',160);


-- 6) Bookings (ขึ้นกับ Users + Schedules)                
INSERT INTO Bookings (UserID, ScheduleID, Status) VALUES
(1,1,'Confirmed'),
(2,2,'Confirmed'),
(3,4,'Pending'),
(4,5,'Confirmed'),
(5,7,'Cancelled'),
(6,9,'Confirmed');



-- 7) Tickets (ขึ้นกับ Bookings)
INSERT INTO Tickets (BookingID, SeatNumber, PassengerName) VALUES
(1,'A01','Somchai'),
(2,'A02','Anan'),
(3,'B01','Suda'),
(4,'B02','Wichai'),
(5,'C01','Mana'),
(6,'C02','Jane');


-- 8) Payments (ขึ้นกับ Bookings)
INSERT INTO Payments (BookingID, Amount, PaymentMethod) VALUES
(1,120,'QR Code'),
(2,100,'Cash'),
(3,120,'Credit Card'),
(4,100,'Mobile Banking'),
(5,80,'QR Code'),
(6,160,'Cash');


--------------------------


SELECT * FROM Users;
SELECT * FROM Lines;
SELECT * FROM Tickets;
SELECT * FROM Payments;
SELECT * FROM Schedules;
SELECT * FROM Bookings;
SELECT * FROM Stations;

--ดูขบวนรถไฟว่าออกจากสถานีไหน ไปสถานีไหน + จังหวัดอะไรi
SELECT 
    t.TrainName AS ชื่อขบวนรถ,
    so.StationName AS สถานีต้นทาง,
    so.Locations AS จังหวัดต้นทาง,
    sd.StationName AS สถานีปลายทาง,
    sd.Locations AS จังหวัดปลายทาง,
    s.DepartureTime AS เวลาออก,
    s.ArrivalTime AS เวลาถึง,
    s.Price AS ราคา
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations so ON s.OriginStationID = so.StationID
JOIN Stations sd ON s.DestinationStationID = sd.StationID


SELECT 
    s.ScheduleID,
    t.TrainName,
    so.StationName AS OriginStation,
    so.Locations AS OriginProvince,
    sd.StationName AS DestinationStation,
    sd.Locations AS DestinationProvince,
    s.DepartureTime,
    s.ArrivalTime
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations so ON s.OriginStationID = so.StationID
JOIN Stations sd ON s.DestinationStationID = sd.StationID
ORDER BY s.DepartureTime;


-- แสดงข้อมูลการจองของผู้ใช้
SELECT 
    b.BookingID,
    u.FullName,
    u.Email,
    u.Phone,
    t.TrainName,
    so.StationName AS OriginStation,
    sd.StationName AS DestinationStation,
    s.DepartureTime,
    s.ArrivalTime,
    b.Status
FROM Bookings b
JOIN Users u ON b.UserID = u.UserID
JOIN Schedules s ON b.ScheduleID = s.ScheduleID
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations so ON s.OriginStationID = so.StationID
JOIN Stations sd ON s.DestinationStationID = sd.StationID
ORDER BY b.BookingID;

-- สายที่ใช้เวลาเดินทางนานที่สุด
SELECT 
    t.TrainName,
    so.StationName AS OriginStation,
    sd.StationName AS DestinationStation,
    s.DepartureTime,
    s.ArrivalTime,
    (s.ArrivalTime - s.DepartureTime) AS TravelDuration
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations so ON s.OriginStationID = so.StationID
JOIN Stations sd ON s.DestinationStationID = sd.StationID
ORDER BY TravelDuration DESC
LIMIT 1;

-- กรุงเทพอภิวัฒน์ ไป ศาลายา รถจะมาถึงกี่โมง ชื่อขบวนอะไร
SELECT 
    t.TrainName,
    s.DepartureTime,
    s.ArrivalTime,
    s.Price
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations so ON s.OriginStationID = so.StationID
JOIN Stations sd ON s.DestinationStationID = sd.StationID
WHERE so.StationName = 'กรุงเทพอภิวัฒน์'
  AND sd.StationName = 'ศาลายา';


-------------test 
  SELECT 
    SUM(s.Price) AS TotalPrice
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations os ON s.OriginStationID = os.StationID
JOIN Stations ds ON s.DestinationStationID = ds.StationID
WHERE t.TrainType = 'แอร์'
AND (
      (os.StationName = 'นครปฐม' AND ds.StationName = 'กรุงเทพอภิวัฒน์')
   OR (os.StationName = 'กรุงเทพอภิวัฒน์' AND ds.StationName = 'ดอนเมือง')
);


SELECT MIN(s.Price) AS CheapestPrice
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations os ON s.OriginStationID = os.StationID
JOIN Stations ds ON s.DestinationStationID = ds.StationID
WHERE os.StationName = 'นครปฐม'
  AND ds.StationName = 'กรุงเทพอภิวัฒน์'
  AND t.TrainType = 'แอร์';

SELECT 
    s.Price AS Price_NakhonPathom_to_KrungThepA,
    t.TrainName
FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations os ON s.OriginStationID = os.StationID
JOIN Stations ds ON s.DestinationStationID = ds.StationID
WHERE os.StationName = 'กรุงเทพอภิวัฒน์'
  AND ds.StationName = 'ดอนเมือง'
  AND t.TrainType = 'แอร์';


----------test2 แสดงค่าโดยสาร นครป
SELECT 
    (
        SELECT MIN(s.Price)
        FROM Schedules s
        JOIN Trains t ON s.TrainID = t.TrainID
        JOIN Stations os ON s.OriginStationID = os.StationID
        JOIN Stations ds ON s.DestinationStationID = ds.StationID
        WHERE os.StationName = 'นครปฐม'
          AND ds.StationName = 'กรุงเทพอภิวัฒน์'
          AND t.TrainType = 'แอร์'
    )
    +
    (
        SELECT MIN(s.Price)
        FROM Schedules s
        JOIN Trains t ON s.TrainID = t.TrainID
        JOIN Stations os ON s.OriginStationID = os.StationID
        JOIN Stations ds ON s.DestinationStationID = ds.StationID
        WHERE os.StationName = 'กรุงเทพอภิวัฒน์'
          AND ds.StationName = 'ดอนเมือง'
          AND t.TrainType = 'แอร์'
    )
    AS TotalCheapestPrice;
----------แสดงราคาค่าโดยสาร นครปฐม ไป ดอนเมือง โดยรถแอร์(สองต่อ)
SELECT
    MIN(CASE 
            WHEN os.StationName = 'นครปฐม'
             AND ds.StationName = 'กรุงเทพอภิวัฒน์'
            THEN s.Price
        END) AS Price_NakhonPathom_to_KrungThepAphiwat,

    MIN(CASE 
            WHEN os.StationName = 'กรุงเทพอภิวัฒน์'
             AND ds.StationName = 'ดอนเมือง'
            THEN s.Price
        END) AS Price_KrungThepAphiwat_to_Donmuang,

    MIN(CASE 
            WHEN os.StationName = 'นครปฐม'
             AND ds.StationName = 'กรุงเทพอภิวัฒน์'
            THEN s.Price
        END)
    +
    MIN(CASE 
            WHEN os.StationName = 'กรุงเทพอภิวัฒน์'
             AND ds.StationName = 'ดอนเมือง'
            THEN s.Price
        END) AS TotalPrice

FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations os ON s.OriginStationID = os.StationID
JOIN Stations ds ON s.DestinationStationID = ds.StationID
WHERE t.TrainType = 'แอร์'
AND (
      (os.StationName = 'นครปฐม' AND ds.StationName = 'กรุงเทพอภิวัฒน์')
   OR (os.StationName = 'กรุงเทพอภิวัฒน์' AND ds.StationName = 'ดอนเมือง')
); 


------------------ แสดงราคาค่าโดยสาร นครปฐม ไป ดอนเมือง โดยรถแอร์และผ่านสถานีอะไรบ้าง (สองต่อ)
SELECT

--- ราคาช่วงต่อที่ 1 : นครปฐม ไป  กรุงเทพอภิวัฒน์
    MIN(CASE 
            WHEN os.StationName = 'นครปฐม'
             AND ds.StationName = 'กรุงเทพอภิวัฒน์'
            THEN s.Price
        END) AS Price_NakhonPathom_to_KrungThepAphiwat,

--- ราคาช่วงต่อที่ที่ 2 : กรุงเทพอภิวัฒน์ ไป  ดอนเมือง
    MIN(CASE 
            WHEN os.StationName = 'กรุงเทพอภิวัฒน์'
             AND ds.StationName = 'ดอนเมือง'
            THEN s.Price
        END) AS Price_KrungThepAphiwat_to_Donmuang,

--- ราคารวมของทั้ง 2 ต่อ
    MIN(CASE 
            WHEN os.StationName = 'นครปฐม'
             AND ds.StationName = 'กรุงเทพอภิวัฒน์'
            THEN s.Price
        END)
    +
    MIN(CASE 
            WHEN os.StationName = 'กรุงเทพอภิวัฒน์'
             AND ds.StationName = 'ดอนเมือง'
            THEN s.Price
        END) AS TotalPrice,

-- แสดงสถานีที่ผ่านช่วงต่อที่ 1
(
        SELECT STRING_AGG(st.StationName, ' → ' ORDER BY st.StationOrder DESC)
        FROM Stations st
        WHERE st.LineID = 1
          AND st.StationOrder BETWEEN 1 AND 4
    ) AS Route_NakhonPathom_to_KrungThepAphiwat,

--- แสดงสถานีที่ผ่านช่วงต่อที่ 2
    (
        SELECT STRING_AGG(st.StationName, ' → ' ORDER BY st.StationOrder)
        FROM Stations st
        WHERE st.LineID = 2
          AND st.StationOrder BETWEEN 1 AND 3
    ) AS Route_KrungThepAphiwat_to_Donmuang

FROM Schedules s
JOIN Trains t ON s.TrainID = t.TrainID
JOIN Stations os ON s.OriginStationID = os.StationID
JOIN Stations ds ON s.DestinationStationID = ds.StationID

WHERE t.TrainType = 'แอร์'
AND (
      (os.StationName = 'นครปฐม' AND ds.StationName = 'กรุงเทพอภิวัฒน์')
   OR (os.StationName = 'กรุงเทพอภิวัฒน์' AND ds.StationName = 'ดอนเมือง')
);